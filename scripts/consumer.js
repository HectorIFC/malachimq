#!/usr/bin/env node

/**
 * MalachiMQ Consumer - Node.js Client with Authentication
 * 
 * Consumes messages from MalachiMQ via TCP with username/password authentication.
 * 
 * Usage:
 *   node consumer.js                    # Consumes from 'test' queue
 *   node consumer.js orders             # Consumes from 'orders' queue
 *   node consumer.js --verbose          # Shows full message payload
 * 
 * Environment variables:
 *   MALACHIMQ_HOST     Server host (default: localhost)
 *   MALACHIMQ_PORT     Server port (default: 4040)
 *   MALACHIMQ_QUEUE    Queue name (default: test)
 *   MALACHIMQ_USER     Username (default: consumer)
 *   MALACHIMQ_PASS     Password (default: consumer123)
 *   MALACHIMQ_LOCALE   Locale: pt_BR | en_US (default: pt_BR)
 */

const net = require('net');
const { t } = require('./i18n');

const CONFIG = {
  host: process.env.MALACHIMQ_HOST || 'localhost',
  port: parseInt(process.env.MALACHIMQ_PORT) || 4040,
  queueName: process.env.MALACHIMQ_QUEUE || 'test',
  username: process.env.MALACHIMQ_USER || 'consumer',
  password: process.env.MALACHIMQ_PASS || 'consumer123',
};

const colors = {
  green: (text) => `\x1b[32m${text}\x1b[0m`,
  red: (text) => `\x1b[31m${text}\x1b[0m`,
  yellow: (text) => `\x1b[33m${text}\x1b[0m`,
  cyan: (text) => `\x1b[36m${text}\x1b[0m`,
  gray: (text) => `\x1b[90m${text}\x1b[0m`,
  magenta: (text) => `\x1b[35m${text}\x1b[0m`,
};

/**
 * MalachiMQ Consumer Client with authentication
 */
class MalachiMQConsumer {
  constructor(options = {}) {
    this.host = options.host || CONFIG.host;
    this.port = options.port || CONFIG.port;
    this.username = options.username || CONFIG.username;
    this.password = options.password || CONFIG.password;
    this.queueName = options.queueName || CONFIG.queueName;
    this.client = null;
    this.token = null;
    this.messageCount = 0;
    this.onMessage = options.onMessage || null;
    this.verbose = options.verbose || false;
  }

  async connect() {
    return new Promise((resolve, reject) => {
      this.client = net.createConnection(this.port, this.host, async () => {
        try {
          await this._authenticate();
          resolve(this);
        } catch (err) {
          this.client.end();
          reject(err);
        }
      });

      this.client.on('error', (err) => {
        reject(err);
      });
    });
  }

  _authenticate() {
    return new Promise((resolve, reject) => {
      const authMsg = JSON.stringify({
        action: 'auth',
        username: this.username,
        password: this.password,
      }) + '\n';

      let response = '';
      let timeoutId = null;

      const onData = (data) => {
        response += data.toString();
        if (response.includes('\n')) {
          clearTimeout(timeoutId);
          this.client.removeListener('data', onData);
          try {
            const parsed = JSON.parse(response.trim());
            if (parsed.s === 'ok' && parsed.token) {
              this.token = parsed.token;
              resolve(parsed);
            } else {
              reject(new Error(t('auth_failed_error') || 'Authentication failed'));
            }
          } catch (e) {
            reject(new Error('Invalid auth response'));
          }
        }
      };

      this.client.on('data', onData);
      this.client.write(authMsg);

      timeoutId = setTimeout(() => {
        if (this.client) {
          this.client.removeListener('data', onData);
        }
        reject(new Error(t('timeout_error') || 'Authentication timeout'));
      }, 5000);
    });
  }

  async subscribe(queueName) {
    if (!this.client || !this.token) {
      throw new Error(t('not_connected_error') || 'Not connected');
    }

    this.queueName = queueName || this.queueName;

    return new Promise((resolve, reject) => {
      const subscribeMsg = JSON.stringify({
        action: 'subscribe',
        queue_name: this.queueName,
      }) + '\n';

      let response = '';
      let timeoutId = null;
      let resolved = false;

      const onData = (data) => {
        response += data.toString();
        
        // Process all complete lines in the buffer
        while (response.includes('\n')) {
          const newlineIndex = response.indexOf('\n');
          const line = response.slice(0, newlineIndex).trim();
          response = response.slice(newlineIndex + 1);

          if (!line) continue;

          try {
            const parsed = JSON.parse(line);

            // Handle subscription confirmation
            if (!resolved && parsed.s === 'ok') {
              clearTimeout(timeoutId);
              resolved = true;
              resolve(parsed);
              continue;
            }

            // Handle subscription error
            if (!resolved && parsed.s === 'err') {
              clearTimeout(timeoutId);
              resolved = true;
              reject(new Error(parsed.reason || 'Subscription failed'));
              continue;
            }

            // Handle incoming messages
            if (parsed.queue_message) {
              this._handleMessage(parsed.queue_message);
            }
          } catch (e) {
            // Ignore parse errors for partial data
          }
        }
      };

      this.client.on('data', onData);
      this.client.write(subscribeMsg);

      timeoutId = setTimeout(() => {
        if (!resolved) {
          reject(new Error(t('timeout_error') || 'Subscription timeout'));
        }
      }, 5000);
    });
  }

  _handleMessage(message) {
    this.messageCount++;
    
    if (this.onMessage) {
      this.onMessage(message, this.messageCount);
    } else {
      this._defaultMessageHandler(message);
    }
  }

  _defaultMessageHandler(message) {
    const timestamp = new Date().toISOString().slice(11, 23);
    
    if (this.verbose) {
      console.log(colors.green(`\n✓ [${this.messageCount}] `) + colors.gray(timestamp));
      console.log(colors.cyan('  Payload:'), JSON.stringify(message.payload, null, 2));
      if (message.headers && Object.keys(message.headers).length > 0) {
        console.log(colors.magenta('  Headers:'), JSON.stringify(message.headers));
      }
    } else {
      const payloadPreview = typeof message.payload === 'object' 
        ? JSON.stringify(message.payload).slice(0, 60) + '...'
        : String(message.payload).slice(0, 60);
      console.log(
        colors.green(`✓ [${this.messageCount}]`) + 
        colors.gray(` ${timestamp}`) + 
        ` ${payloadPreview}`
      );
    }
  }

  close() {
    if (this.client) {
      this.client.end();
      this.client = null;
      this.token = null;
    }
  }

  getStats() {
    return {
      messagesReceived: this.messageCount,
      queueName: this.queueName,
      connected: this.client !== null,
    };
  }
}

/**
 * Creates and starts a consumer
 */
async function startConsumer(queueName, options = {}) {
  const consumer = new MalachiMQConsumer({
    queueName,
    ...options,
  });

  await consumer.connect();
  await consumer.subscribe(queueName);
  
  return consumer;
}

/**
 * Main consumer loop
 */
async function main() {
  const args = process.argv.slice(2);
  const verbose = args.includes('--verbose') || args.includes('-v');
  const queueName = args.find(a => !a.startsWith('-')) || CONFIG.queueName;

  console.log(colors.cyan(`\n📥 MalachiMQ Consumer`));
  console.log(colors.gray(`   Host: ${CONFIG.host}:${CONFIG.port}`));
  console.log(colors.gray(`   User: ${CONFIG.username}`));
  console.log(colors.gray(`   Queue: ${queueName}`));
  console.log(colors.gray(`   Verbose: ${verbose ? 'yes' : 'no'}`));
  console.log(colors.yellow(`   Press Ctrl+C to stop\n`));

  try {
    const consumer = new MalachiMQConsumer({
      queueName,
      verbose,
    });

    await consumer.connect();
    console.log(colors.green(`✓ Connected (authenticated as ${CONFIG.username})`));

    await consumer.subscribe(queueName);
    console.log(colors.green(`✓ Subscribed to queue '${queueName}'`));
    console.log(colors.gray(`\nWaiting for messages...\n`));

    // Keep the process running
    process.on('SIGINT', () => {
      const stats = consumer.getStats();
      console.log(colors.yellow(`\n\n⏹ Stopping consumer...`));
      console.log(colors.cyan(`📊 Statistics:`));
      console.log(colors.gray(`   Messages received: ${stats.messagesReceived}`));
      consumer.close();
      process.exit(0);
    });

    // Prevent the process from exiting
    process.stdin.resume();

  } catch (err) {
    console.error(colors.red(`\n❌ Error: ${err.message}`));
    console.error(colors.gray(`   Check if MalachiMQ is running on ${CONFIG.host}:${CONFIG.port}\n`));
    process.exit(1);
  }
}

// Help message
function showHelp() {
  console.log(`
${colors.cyan('📥 MalachiMQ Consumer')}

${colors.yellow('Usage:')}
  node consumer.js [options] [queue_name]

${colors.yellow('Options:')}
  -h, --help     Show this help message
  -v, --verbose  Show full message payload and headers

${colors.yellow('Examples:')}
  node consumer.js              # Consume from 'test' queue
  node consumer.js orders       # Consume from 'orders' queue
  node consumer.js -v           # Verbose mode with full payloads
  node consumer.js orders -v    # Consume 'orders' with verbose mode

${colors.yellow('Environment Variables:')}
  MALACHIMQ_HOST   Server host (default: localhost)
  MALACHIMQ_PORT   Server port (default: 4040)
  MALACHIMQ_QUEUE  Default queue name (default: test)
  MALACHIMQ_USER   Username (default: consumer)
  MALACHIMQ_PASS   Password (default: consumer123)
  MALACHIMQ_LOCALE Locale: pt_BR | en_US (default: pt_BR)
`);
}

module.exports = { MalachiMQConsumer, startConsumer };

if (require.main === module) {
  const args = process.argv.slice(2);
  
  if (args.includes('--help') || args.includes('-h')) {
    showHelp();
  } else {
    main();
  }
}
