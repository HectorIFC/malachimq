#!/usr/bin/env node

/**
 * MalachiMQ Channel Subscriber
 * 
 * Subscribes to channels and receives messages in real-time.
 * Best-effort delivery - only receives messages while connected.
 * 
 * Usage:
 *   node channel-subscriber.js                    # Subscribe to 'news' channel
 *   node channel-subscriber.js sports             # Subscribe to 'sports' channel
 *   node channel-subscriber.js --verbose          # Show full payloads
 *   node channel-subscriber.js sports alerts      # Subscribe to multiple channels
 * 
 * Environment variables:
 *   MALACHIMQ_HOST     Server host (default: localhost)
 *   MALACHIMQ_PORT     Server port (default: 4040)
 *   MALACHIMQ_CHANNEL  Default channel name (default: news)
 *   MALACHIMQ_USER     Username (default: consumer)
 *   MALACHIMQ_PASS     Password (default: consumer123)
 */

const net = require('net');

const CONFIG = {
  host: process.env.MALACHIMQ_HOST || 'localhost',
  port: parseInt(process.env.MALACHIMQ_PORT) || 4040,
  channelName: process.env.MALACHIMQ_CHANNEL || 'news',
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

class ChannelSubscriber {
  constructor(options = {}) {
    this.host = options.host || CONFIG.host;
    this.port = options.port || CONFIG.port;
    this.username = options.username || CONFIG.username;
    this.password = options.password || CONFIG.password;
    this.channels = options.channels || [];
    this.client = null;
    this.token = null;
    this.messageCount = 0;
    this.onMessage = options.onMessage || null;
    this.verbose = options.verbose || false;
    this.autoReconnect = options.autoReconnect !== false;
    this.reconnectAttempts = 0;
    this.maxReconnectAttempts = options.maxReconnectAttempts || 10;
    this.baseReconnectDelay = options.baseReconnectDelay || 1000;
    this.maxReconnectDelay = options.maxReconnectDelay || 30000;
    this.isReconnecting = false;
    this.shouldStop = false;
  }

  async connect() {
    return new Promise((resolve, reject) => {
      this.client = net.createConnection(this.port, this.host, async () => {
        try {
          await this._authenticate();
          this.reconnectAttempts = 0;
          resolve(this);
        } catch (err) {
          this.client.end();
          reject(err);
        }
      });

      this.client.on('error', (err) => {
        if (!this.isReconnecting) {
          this._handleDisconnect(err);
        }
        reject(err);
      });

      this.client.on('close', () => {
        if (!this.shouldStop && !this.isReconnecting) {
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

    const delay = Math.min(
      this.baseReconnectDelay * Math.pow(2, this.reconnectAttempts - 1) + Math.random() * 1000,
      this.maxReconnectDelay
    );

    console.log(colors.yellow(`\n🔄 Reconnecting in ${Math.round(delay / 1000)}s (attempt ${this.reconnectAttempts}/${this.maxReconnectAttempts})...`));

    setTimeout(async () => {
      try {
        if (this.client) {
          this.client.removeAllListeners();
          this.client.destroy();
          this.client = null;
        }

        await this.connect();
        console.log(colors.green(`✓ Reconnected successfully`));

        for (const channel of this.channels) {
          await this.subscribe(channel);
          console.log(colors.green(`✓ Resubscribed to channel '${channel}'`));
        }
        console.log(colors.gray(`\nWaiting for messages...\n`));

        this.isReconnecting = false;
      } catch (err) {
        this.isReconnecting = false;
      }
    }, delay);
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
              reject(new Error('Authentication failed'));
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
        reject(new Error('Authentication timeout'));
      }, 5000);
    });
  }

  async subscribe(channelName) {
    if (!this.client || !this.token) {
      throw new Error('Not connected');
    }

    if (!this.channels.includes(channelName)) {
      this.channels.push(channelName);
    }

    return new Promise((resolve, reject) => {
      const subscribeMsg = JSON.stringify({
        action: 'channel_subscribe',
        channel_name: channelName,
      }) + '\n';

      let response = '';
      let timeoutId = null;
      let resolved = false;

      const onData = (data) => {
        response += data.toString();
        
        while (response.includes('\n')) {
          const newlineIndex = response.indexOf('\n');
          const line = response.slice(0, newlineIndex).trim();
          response = response.slice(newlineIndex + 1);

          if (!line) continue;

          try {
            const parsed = JSON.parse(line);

            if (!resolved && parsed.s === 'ok') {
              clearTimeout(timeoutId);
              resolved = true;
              resolve(parsed);
              continue;
            }

            if (!resolved && parsed.s === 'err') {
              clearTimeout(timeoutId);
              resolved = true;
              reject(new Error(parsed.reason || 'Subscription failed'));
              continue;
            }

            if (parsed.shutdown) {
              console.log(colors.yellow(`\n⚠️ Server shutting down: ${parsed.reason || 'unknown'}`));
              continue;
            }

            if (parsed.channel_message) {
              this._handleMessage(parsed.channel_message);
            }

            if (parsed.kicked_from_channel) {
              console.log(colors.red(`\n❌ Kicked from channel: ${parsed.kicked_from_channel}`));
            }
          } catch (e) {
            // Ignore parse errors
          }
        }
      };

      this.client.on('data', onData);
      this.client.write(subscribeMsg);

      timeoutId = setTimeout(() => {
        if (!resolved) {
          reject(new Error('Subscription timeout'));
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
      console.log(colors.green(`\n📬 [${this.messageCount}] `) + colors.gray(timestamp));
      console.log(colors.cyan('  Channel:'), message.channel);
      console.log(colors.cyan('  Payload:'), JSON.stringify(message.payload, null, 2));
      if (message.headers && Object.keys(message.headers).length > 0) {
        console.log(colors.magenta('  Headers:'), JSON.stringify(message.headers));
      }
    } else {
      const payloadPreview = typeof message.payload === 'object' 
        ? JSON.stringify(message.payload).slice(0, 60) + '...'
        : String(message.payload).slice(0, 60);
      console.log(
        colors.green(`📬 [${this.messageCount}]`) + 
        colors.gray(` ${timestamp}`) + 
        colors.cyan(` [${message.channel}]`) +
        ` ${payloadPreview}`
      );
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

  getStats() {
    return {
      messagesReceived: this.messageCount,
      channels: this.channels,
      connected: this.client !== null && !this.isReconnecting,
      autoReconnect: this.autoReconnect,
      reconnectAttempts: this.reconnectAttempts,
    };
  }
}

async function main() {
  const args = process.argv.slice(2);
  const verbose = args.includes('--verbose') || args.includes('-v');
  const noReconnect = args.includes('--no-reconnect');
  
  const channelNames = args.filter(a => !a.startsWith('-')) || [CONFIG.channelName];
  if (channelNames.length === 0) {
    channelNames.push(CONFIG.channelName);
  }

  console.log(colors.cyan(`\n📡 MalachiMQ Channel Subscriber`));
  console.log(colors.gray(`   Host: ${CONFIG.host}:${CONFIG.port}`));
  console.log(colors.gray(`   User: ${CONFIG.username}`));
  console.log(colors.gray(`   Channels: ${channelNames.join(', ')}`));
  console.log(colors.gray(`   Verbose: ${verbose ? 'yes' : 'no'}`));
  console.log(colors.gray(`   Auto-Reconnect: ${noReconnect ? 'no' : 'yes'}`));
  console.log(colors.yellow(`   Press Ctrl+C to stop\n`));

  try {
    const subscriber = new ChannelSubscriber({
      channels: [],
      verbose,
      autoReconnect: !noReconnect,
    });

    await subscriber.connect();
    console.log(colors.green(`✓ Connected (authenticated as ${CONFIG.username})`));

    for (const channelName of channelNames) {
      await subscriber.subscribe(channelName);
      console.log(colors.green(`✓ Subscribed to channel '${channelName}'`));
    }
    console.log(colors.gray(`\nWaiting for messages...\n`));
    console.log(colors.magenta(`📝 Note: Only messages published while subscribed will be received`));
    console.log(colors.magenta(`   (no buffering - best-effort delivery)\n`));

    process.on('SIGINT', () => {
      const stats = subscriber.getStats();
      console.log(colors.yellow(`\n\n⏹ Stopping subscriber...`));
      console.log(colors.cyan(`📊 Statistics:`));
      console.log(colors.gray(`   Messages received: ${stats.messagesReceived}`));
      console.log(colors.gray(`   Channels: ${stats.channels.join(', ')}`));
      if (stats.reconnectAttempts > 0) {
        console.log(colors.yellow(`   Reconnect attempts: ${stats.reconnectAttempts}`));
      }
      subscriber.close();
      process.exit(0);
    });

    process.stdin.resume();

  } catch (err) {
    console.error(colors.red(`\n❌ Error: ${err.message}`));
    console.error(colors.gray(`   Check if MalachiMQ is running on ${CONFIG.host}:${CONFIG.port}\n`));
    process.exit(1);
  }
}

function showHelp() {
  console.log(`
${colors.cyan('📡 MalachiMQ Channel Subscriber')}

${colors.yellow('Usage:')}
  node channel-subscriber.js [options] [channel_name...]

${colors.yellow('Options:')}
  -h, --help       Show this help message
  -v, --verbose    Show full message payload and headers
  --no-reconnect   Disable automatic reconnection on disconnect

${colors.yellow('Examples:')}
  node channel-subscriber.js              # Subscribe to 'news' channel
  node channel-subscriber.js sports       # Subscribe to 'sports' channel
  node channel-subscriber.js news sports  # Subscribe to multiple channels
  node channel-subscriber.js -v           # Verbose mode with full payloads
  node channel-subscriber.js alerts --no-reconnect

${colors.yellow('Environment Variables:')}
  MALACHIMQ_HOST     Server host (default: localhost)
  MALACHIMQ_PORT     Server port (default: 4040)
  MALACHIMQ_CHANNEL  Default channel name (default: news)
  MALACHIMQ_USER     Username (default: consumer)
  MALACHIMQ_PASS     Password (default: consumer123)

${colors.yellow('Channel Behavior:')}
  • ${colors.magenta('Best-effort delivery')} - no message persistence
  • Only receives messages ${colors.magenta('while subscribed')}
  • No buffering - missed messages are lost
  • Real-time broadcast to all subscribers
  • best-effort delivery semantics

${colors.yellow('Auto-Reconnect:')}
  By default, the subscriber will automatically reconnect if disconnected.
  Uses exponential backoff (1s, 2s, 4s... up to 30s) with up to 10 attempts.
  The server sends a shutdown notification before closing connections.
`);
}

module.exports = { ChannelSubscriber };

if (require.main === module) {
  const args = process.argv.slice(2);
  
  if (args.includes('--help') || args.includes('-h')) {
    showHelp();
  } else {
    main();
  }
}
