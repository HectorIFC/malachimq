#!/usr/bin/env node

/**
 * MalachiMQ Channel Publisher
 * 
 * Publishes messages to channels with best-effort delivery.
 * Messages are only delivered to active subscribers (no buffering).
 * 
 * Usage:
 *   node channel-publisher.js                      # Publish to 'news' channel
 *   node channel-publisher.js sports               # Publish to 'sports' channel
 *   node channel-publisher.js alerts 100           # Publish 100 messages
 *   node channel-publisher.js --continuous         # Continuous publishing (1 msg/sec)
 * 
 * Environment variables:
 *   MALACHIMQ_HOST     Server host (default: localhost)
 *   MALACHIMQ_PORT     Server port (default: 4040)
 *   MALACHIMQ_CHANNEL  Channel name (default: news)
 *   MALACHIMQ_USER     Username (default: producer)
 *   MALACHIMQ_PASS     Password (default: producer123)
 */

const net = require('net');
const { MalachiMQClient } = require('./producer');

const CONFIG = {
  host: process.env.MALACHIMQ_HOST || 'localhost',
  port: parseInt(process.env.MALACHIMQ_PORT) || 4040,
  channelName: process.env.MALACHIMQ_CHANNEL || 'news',
  username: process.env.MALACHIMQ_USER || 'producer',
  password: process.env.MALACHIMQ_PASS || 'producer123',
};

const colors = {
  green: (text) => `\x1b[32m${text}\x1b[0m`,
  red: (text) => `\x1b[31m${text}\x1b[0m`,
  yellow: (text) => `\x1b[33m${text}\x1b[0m`,
  cyan: (text) => `\x1b[36m${text}\x1b[0m`,
  gray: (text) => `\x1b[90m${text}\x1b[0m`,
  magenta: (text) => `\x1b[35m${text}\x1b[0m`,
};

async function publishToChannel(client, channelName, payload, headers = {}) {
  if (!client.client || !client.token || !client.isConnected) {
    throw new Error('Not connected');
  }

  return new Promise((resolve, reject) => {
    const message = JSON.stringify({
      action: 'channel_publish',
      channel_name: channelName,
      payload: payload,
      headers: headers,
    }) + '\n';

    client.pendingResolve = resolve;
    client.pendingReject = reject;

    client.pendingTimeout = setTimeout(() => {
      client._clearPending();
      reject(new Error('Timeout'));
    }, 5000);

    try {
      client.client.write(message);
    } catch (err) {
      client._clearPending();
      reject(err);
    }

    client._processBuffer();
  });
}

async function publishMessages(count) {
  console.log(colors.cyan(`\n📢 MalachiMQ Channel Publisher`));
  console.log(colors.gray(`   Host: ${CONFIG.host}:${CONFIG.port}`));
  console.log(colors.gray(`   User: ${CONFIG.username}`));
  console.log(colors.gray(`   Channel: ${CONFIG.channelName}`));
  console.log(colors.gray(`   Messages: ${count}\n`));

  const client = new MalachiMQClient({
    host: CONFIG.host,
    port: CONFIG.port,
    username: CONFIG.username,
    password: CONFIG.password,
  });

  await client.connect();
  console.log(colors.green(`✓ Connected (authenticated as ${CONFIG.username})\n`));

  const startTime = Date.now();
  let success = 0;
  let errors = 0;

  for (let i = 1; i <= count; i++) {
    try {
      const payload = {
        id: i,
        headline: `Breaking News #${i}`,
        timestamp: new Date().toISOString(),
        channel: CONFIG.channelName,
      };

      const headers = {
        'x-message-id': `ch-msg-${i}-${Date.now()}`,
        'x-priority': i % 5 === 0 ? 'urgent' : 'normal',
      };

      const response = await publishToChannel(client, CONFIG.channelName, payload, headers);

      if (response.s === 'ok') {
        success++;
        if (count <= 20 || i % Math.ceil(count / 10) === 0) {
          console.log(colors.green(`✓ [${i}/${count}]`) + ` Published to channel`);
        }
      } else {
        errors++;
        console.log(colors.red(`✗ [${i}/${count}]`) + ` Error: ${JSON.stringify(response)}`);
      }
    } catch (err) {
      errors++;
      console.log(colors.red(`✗ [${i}/${count}]`) + ` Error: ${err.message}`);
    }
  }

  client.close();

  const duration = Date.now() - startTime;
  const rate = Math.round((success / duration) * 1000);

  console.log(colors.cyan(`\n📊 Results`));
  console.log(colors.green(`   Success: ${success}`));
  if (errors > 0) console.log(colors.red(`   Errors: ${errors}`));
  console.log(colors.gray(`   Time: ${duration}ms`));
  console.log(colors.gray(`   Rate: ${rate} msgs/second\n`));
  console.log(colors.magenta(`📝 Note: Messages are only delivered to active subscribers`));
  console.log(colors.magenta(`   (no buffering - dropped if no subscribers are listening)\n`));
}

async function publishContinuous() {
  console.log(colors.cyan(`\n📢 MalachiMQ Channel Publisher (Continuous)`));
  console.log(colors.gray(`   Host: ${CONFIG.host}:${CONFIG.port}`));
  console.log(colors.gray(`   User: ${CONFIG.username}`));
  console.log(colors.gray(`   Channel: ${CONFIG.channelName}`));
  console.log(colors.gray(`   Auto-Reconnect: yes`));
  console.log(colors.yellow(`   Press Ctrl+C to stop\n`));

  const client = new MalachiMQClient({ 
    host: CONFIG.host,
    port: CONFIG.port,
    username: CONFIG.username,
    password: CONFIG.password,
    autoReconnect: true 
  });
  
  await client.connect();
  console.log(colors.green(`✓ Connected (authenticated as ${CONFIG.username})\n`));

  let count = 0;
  let successCount = 0;
  let errorCount = 0;

  const interval = setInterval(async () => {
    count++;
    
    if (client.isReconnecting) {
      console.log(colors.yellow(`⏸ [${count}]`) + ` Waiting for reconnection...`);
      return;
    }

    try {
      const payload = {
        id: count,
        headline: `Live Update #${count}`,
        timestamp: new Date().toISOString(),
        uptime: process.uptime(),
      };

      const response = await publishToChannel(
        client,
        CONFIG.channelName,
        payload,
        { 'x-continuous': true }
      );

      if (response.s === 'ok') {
        successCount++;
        console.log(colors.green(`✓ [${count}]`) + ` ${new Date().toISOString()}`);
      } else {
        errorCount++;
        console.log(colors.red(`✗ [${count}]`) + ` Error: ${JSON.stringify(response)}`);
      }
    } catch (err) {
      errorCount++;
      console.log(colors.red(`✗ [${count}]`) + ` Error: ${err.message}`);
    }
  }, 1000);

  process.on('SIGINT', () => {
    console.log(colors.yellow(`\n\n⏹ Stopping...`));
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
      await publishContinuous();
    } else if (args.includes('--help') || args.includes('-h')) {
      console.log(`
${colors.cyan('📢 MalachiMQ Channel Publisher')}

${colors.yellow('Usage:')}
  node channel-publisher.js [options] [channel_name] [count]

${colors.yellow('Options:')}
  -h, --help        Show this help message
  -c, --continuous  Publish continuously (1 msg/second)

${colors.yellow('Examples:')}
  node channel-publisher.js                    # Publish 10 messages to 'news'
  node channel-publisher.js sports             # Publish 10 messages to 'sports'
  node channel-publisher.js alerts 100         # Publish 100 messages to 'alerts'
  node channel-publisher.js --continuous       # Continuous publishing

${colors.yellow('Environment Variables:')}
  MALACHIMQ_HOST     Server host (default: localhost)
  MALACHIMQ_PORT     Server port (default: 4040)
  MALACHIMQ_CHANNEL  Default channel name (default: news)
  MALACHIMQ_USER     Username (default: producer)
  MALACHIMQ_PASS     Password (default: producer123)

${colors.yellow('Channel Behavior:')}
  • ${colors.magenta('Best-effort delivery')} - no message persistence
  • Messages only delivered to ${colors.magenta('active subscribers')}
  • No buffering - dropped if no subscribers
  • best-effort delivery semantics
`);
    } else {
      const channelName = args.find(a => !a.startsWith('-') && isNaN(a)) || CONFIG.channelName;
      const count = parseInt(args.find(a => !isNaN(a))) || 10;
      
      CONFIG.channelName = channelName;
      await publishMessages(count);
    }
  } catch (err) {
    console.error(colors.red(`\n❌ Error: ${err.message}`));
    console.error(colors.gray(`   Check if MalachiMQ is running on ${CONFIG.host}:${CONFIG.port}\n`));
    process.exit(1);
  }
}

if (require.main === module) {
  main();
}

module.exports = { publishToChannel };
