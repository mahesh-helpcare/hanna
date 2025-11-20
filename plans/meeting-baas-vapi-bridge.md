Phase 3: Install MeetingBaaS Base (30 min)
bashcd ~/meet-bot-demo
git clone https://github.com/Meeting-Baas/meet-teams-bot.git
cd meet-teams-bot

# Build it
./run_bot.sh build

# Test basic join (without VAPI yet)
./run_bot.sh run \
  meeting_url=https://meet.google.com/xxx-yyyy-zzz \
  bot_name="Hanna Test"
You should see: Bot joins meeting, records audio to /recordings
Phase 4: Build the VAPI Bridge (3-4 hours)
This is the core work. Create a new service that sits between MeetingBaaS and VAPI:
bashcd ~/meet-bot-demo
mkdir vapi-bridge
cd vapi-bridge
npm init -y
npm install ws node-fetch dotenv
Create the bridge server:
javascript// vapi-bridge/server.js
const WebSocket = require('ws');
const fetch = require('node-fetch');
const fs = require('fs');
require('dotenv').config();

class VAPIBridge {
  constructor() {
    // WebSocket server for MeetingBaaS to connect
    this.meetingBaasServer = new WebSocket.Server({ port: 8080 });
    
    // Connection to VAPI
    this.vapiConnection = null;
    this.meetingConnection = null;
    
    this.setupServers();
  }

  setupServers() {
    // Listen for MeetingBaaS connection
    this.meetingBaasServer.on('connection', (ws) => {
      console.log('MeetingBaaS connected');
      this.meetingConnection = ws;
      
      // When we receive audio from meeting
      ws.on('message', async (audioData) => {
        if (this.vapiConnection && this.vapiConnection.readyState === WebSocket.OPEN) {
          // Forward to VAPI
          this.vapiConnection.send(audioData);
        }
      });

      ws.on('close', () => {
        console.log('MeetingBaaS disconnected');
        this.cleanup();
      });
    });

    console.log('Bridge server listening on port 8080');
  }

  async startVAPICall() {
    // Create VAPI call
    const response = await fetch('https://api.vapi.ai/call/web', {
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${process.env.VAPI_API_KEY}`,
        'Content-Type': 'application/json'
      },
      body: JSON.stringify({
        assistant: {
          firstMessage: "Hello! I'm Hanna, your meeting assistant.",
          model: {
            provider: 'openai',
            model: 'gpt-4o-mini',
            systemPrompt: `You are Hanna, a helpful AI meeting assistant. 
            
You should:
- Listen to meeting conversations
- Respond when someone says "Hanna" followed by a question
- Keep responses concise (under 30 seconds)
- Be helpful and professional
- For demo purposes, you can answer questions about when things are scheduled, general information, etc.

Example interactions:
- "Hanna, when is the product launch?" → Check context and respond
- "Hanna, what did we decide about the budget?" → Summarize if discussed
- "Hanna, can you look up..." → Provide helpful information`
          },
          voice: {
            provider: 'elevenlabs',
            voiceId: 'rachel' // or 'sarah', 'nicole'
          }
        }
      })
    });

    const data = await response.json();
    
    // Connect to VAPI's WebSocket
    this.vapiConnection = new WebSocket(data.webSocketUrl);
    
    this.vapiConnection.on('open', () => {
      console.log('Connected to VAPI');
    });

    // When VAPI responds with audio
    this.vapiConnection.on('message', (audioData) => {
      if (this.meetingConnection && this.meetingConnection.readyState === WebSocket.OPEN) {
        // Send VAPI's audio back to the meeting
        this.meetingConnection.send(audioData);
      }
    });

    this.vapiConnection.on('error', (err) => {
      console.error('VAPI error:', err);
    });
  }

  cleanup() {
    if (this.vapiConnection) this.vapiConnection.close();
    if (this.meetingConnection) this.meetingConnection.close();
  }
}

// Start the bridge
const bridge = new VAPIBridge();

// Start VAPI call after a moment (or trigger via API)
setTimeout(() => {
  bridge.startVAPICall();
}, 2000);

// Handle shutdown
process.on('SIGINT', () => {
  console.log('Shutting down bridge...');
  bridge.cleanup();
  process.exit(0);
});
Environment config:
bashcat > .env <<EOF
VAPI_API_KEY=your_vapi_api_key_here
EOF
Phase 5: Modify MeetingBaaS to Stream Audio (2-3 hours)
You need to modify MeetingBaaS to send audio to your bridge instead of just recording to disk.
bashcd ~/meet-bot-demo/meet-teams-bot
Find the audio capture code (likely in src/audio.ts or similar) and add WebSocket streaming:
javascript// Add to MeetingBaaS audio handler
const WebSocket = require('ws');
const bridgeWs = new WebSocket('ws://localhost:8080');

// When capturing audio chunks
function onAudioData(audioBuffer) {
  // Original: write to file
  fs.writeSync(audioFile, audioBuffer);
  
  // NEW: Also stream to bridge
  if (bridgeWs.readyState === WebSocket.OPEN) {
    bridgeWs.send(audioBuffer);
  }
}

// When receiving audio to play (from bridge/VAPI)
bridgeWs.on('message', (audioData) => {
  // Play this audio into the meeting
  playAudioToMeeting(audioData);
});

function playAudioToMeeting(audioBuffer) {
  // Use FFmpeg to play to virtual input device
  const playProcess = spawn('ffmpeg', [
    '-f', 's16le',
    '-ar', '16000',
    '-ac', '1',
    '-i', 'pipe:0',
    '-f', 'pulse',
    'default'  // or specific sink name
  ]);
  
  playProcess.stdin.write(audioBuffer);
  playProcess.stdin.end();
}
Phase 6: Configure PulseAudio for Bidirectional Audio (1 hour)
bash# Create virtual audio devices
cat > ~/setup-audio.sh <<'EOF'
#!/bin/bash

# Load null sinks (virtual devices)
pactl load-module module-null-sink sink_name=meet_speaker sink_properties=device.description="Meeting_Speaker"
pactl load-module module-null-sink sink_name=meet_mic sink_properties=device.description="Meeting_Mic"

# Create loopback to route audio
pactl load-module module-loopback source=meet_speaker.monitor sink=meet_mic latency_msec=1

echo "Virtual audio configured:"
echo "  meet_speaker - Bot hears from meeting"
echo "  meet_mic - Bot speaks to meeting"
EOF

chmod +x ~/setup-audio.sh
~/setup-audio.sh
Configure the browser to use these devices:
javascript// In Playwright launch options
const browser = await chromium.launch({
  headless: true,
  args: [
    '--use-fake-ui-for-media-stream',
    '--use-fake-device-for-media-stream',
    '--autoplay-policy=no-user-gesture-required',
  ],
  env: {
    PULSE_SINK: 'meet_mic',
    PULSE_SOURCE: 'meet_speaker.monitor'
  }
});
Phase 7: Create a Launch Script (30 min)
bash# ~/meet-bot-demo/launch-hanna.sh
#!/bin/bash

set -e

echo "🎙️  Starting Hanna Demo Bot..."

# Setup audio devices
~/setup-audio.sh

# Start VAPI bridge in background
cd ~/meet-bot-demo/vapi-bridge
node server.js &
BRIDGE_PID=$!

# Wait for bridge to start
sleep 2

# Start the meeting bot with authentication
cd ~/meet-bot-demo/meet-teams-bot
./run_bot.sh run \
  auth_state=~/meet-bot-demo/google-auth.json \
  meeting_url="$1" \
  bot_name="Hanna" \
  audio_output=meet_speaker \
  audio_input=meet_mic

# Cleanup on exit
trap "kill $BRIDGE_PID" EXIT
Make it executable:
bashchmod +x ~/meet-bot-demo/launch-hanna.sh
Phase 8: Test & Demo! (1 hour)
bash# Create a test meeting on meet.google.com
# Get the URL: https://meet.google.com/abc-defg-hij

# Launch Hanna!
~/meet-bot-demo/launch-hanna.sh "https://meet.google.com/abc-defg-hij"
What you should see:

Audio devices configured ✓
VAPI bridge starts ✓
Bot joins meeting as "Hanna" ✓
You say "Hanna, what time is it?"
Bot responds with voice in the meeting ✓

Development Workflow
From your Mac:
bash# SSH with port forwarding for debugging
ssh -L 8080:localhost:8080 ubuntu@your-vm-ip

# Edit code locally, sync to VM
rsync -av ./vapi-bridge/ ubuntu@your-vm-ip:~/meet-bot-demo/vapi-bridge/

# Or use VS Code Remote SSH extension (highly recommended!)
code --remote ssh-remote+your-vm-ip ~/meet-bot-demo
VS Code Remote SSH is amazing for this - feels like local development but runs on the VM.
Cost Breakdown
AWS EC2 t3.medium:

$0.0416/hour = ~$30/month if running 24/7
For demo/dev: Start/stop as needed = $5-10/month

VAPI costs:

~$0.10-0.30 per hour of active conversation
Demo/testing: ~$5-10/month

Total: ~$15-20/month for a development environment
Timeline
Day 1 (4 hours):

Spin up VM, install dependencies (1h)
Set up bot account & authentication (1h)
Install MeetingBaaS, test basic join (2h)

Day 2 (4 hours):

Build VAPI bridge server (2h)
Configure audio routing (1h)
Wire everything together (1h)

Day 3 (2 hours):

Testing & debugging
Polish the demo
Add error handling

Total: ~10 hours over 3 days
Advantages Over Other Paths
vs. macOS (Path A):

Real audio streaming, not caption scraping
Production-quality demo
Actually reusable infrastructure
