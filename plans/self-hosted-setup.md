# Self-Hosted Speaking Bot Setup

Complete guide to run everything yourself without MeetingBaaS API.

## Architecture

```
┌─────────────────────────────────────────────────────┐
│                Your Infrastructure                   │
│                                                      │
│  ┌──────────────────────┐      ┌──────────────────┐│
│  │ speaking-meeting-bot │◄────►│ meet-teams-bot   ││
│  │ (Cloud Run/Docker)   │ WSS  │ (Docker)         ││
│  │ • Pipecat AI         │      │ • Chrome         ││
│  │ • STT/LLM/TTS        │      │ • Joins meetings ││
│  └──────────────────────┘      └──────────────────┘│
│           ▲                            ▲             │
│           │                            │             │
│      API to create bot          Joins Google Meet   │
└───────────┼────────────────────────────┼─────────────┘
            │                            │
         Your API                   Meeting URL
```

## Option 1: Quick Local Test

Best for testing before deploying to production.

### Step 1: Start speaking-meeting-bot locally

```bash
cd /home/angelica/speaking-meeting-bot

# Install dependencies
poetry install
poetry run python -m grpc_tools.protoc --proto_path=./protobufs --python_out=./protobufs frames.proto

# Set environment variables
export OPENAI_API_KEY="sk-..."
export CARTESIA_API_KEY="..."
export DEEPGRAM_API_KEY="..."
export PORT=7014

# Start in one terminal
poetry run uvicorn app:app --host 0.0.0.0 --port 7014
```

### Step 2: Expose with ngrok

```bash
# In another terminal
ngrok http 7014
```

Note the ngrok URL (e.g., `https://abc123.ngrok.io`)

### Step 3: Configure and run meet-teams-bot

Create a config file:

```bash
cd /home/angelica/meet-teams-bot
cat > hanna-bot.config.json << 'EOF'
{
    "id": "hanna-bot",
    "meeting_url": "https://meet.google.com/xxx-yyyy-zzz",
    "bot_name": "Hanna",
    "streaming_input": "wss://YOUR_NGROK_URL/ws/hanna-001",
    "streaming_output": "wss://YOUR_NGROK_URL/ws/hanna-001",
    "streaming_audio_frequency": 24000,
    "enter_message": "Hi! I'm Hanna, your meeting assistant.",
    "recording_mode": "speaker_view",
    "environ": "local"
}
EOF

# Replace YOUR_NGROK_URL with your actual ngrok URL
sed -i 's|YOUR_NGROK_URL|abc123.ngrok.io|g' hanna-bot.config.json

# Run the bot
./run_bot.sh run hanna-bot.config.json
```

## Option 2: Production Deployment (Both on Cloud Run)

Deploy both services to Google Cloud Run.

### Part A: Deploy speaking-meeting-bot

```bash
cd /home/angelica/speaking-meeting-bot

# Set your project
export GCP_PROJECT_ID="your-project-id"

# Deploy
./deploy-cloud-run.sh

# Set API keys
gcloud run services update speaking-meeting-bot --region us-central1 \
  --set-env-vars \
    OPENAI_API_KEY="sk-..." \
    CARTESIA_API_KEY="..." \
    DEEPGRAM_API_KEY="..."

# Get the service URL
SPEAKING_BOT_URL=$(gcloud run services describe speaking-meeting-bot \
  --region us-central1 --format 'value(status.url)')

echo "Speaking bot URL: $SPEAKING_BOT_URL"
```

### Part B: Deploy meet-teams-bot to Cloud Run

We need to create a Cloud Run deployment for meet-teams-bot:

```bash
cd /home/angelica/meet-teams-bot

# Build and push image
gcloud builds submit --tag gcr.io/$GCP_PROJECT_ID/meet-teams-bot

# Deploy (note: this needs special configuration)
gcloud run deploy meet-teams-bot \
  --image gcr.io/$GCP_PROJECT_ID/meet-teams-bot \
  --platform managed \
  --region us-central1 \
  --memory 4Gi \
  --cpu 2 \
  --timeout 3600 \
  --no-cpu-throttling \
  --execution-environment gen2
```

⚠️ **Important:** meet-teams-bot needs a persistent connection to run Chrome. Cloud Run's request-response model isn't ideal for this. Better options:

### Part B Alternative: Deploy meet-teams-bot to Compute Engine or GKE

**Compute Engine (Simpler):**

```bash
# Create a VM
gcloud compute instances create-with-container meet-teams-bot-vm \
  --zone=us-central1-a \
  --machine-type=e2-standard-2 \
  --container-image=gcr.io/$GCP_PROJECT_ID/meet-teams-bot \
  --container-restart-policy=always \
  --boot-disk-size=30GB
```

**Then SSH in and configure:**
```bash
gcloud compute ssh meet-teams-bot-vm --zone=us-central1-a

# Create config file with your speaking-bot URL
cat > /tmp/bot-config.json << EOF
{
    "streaming_input": "wss://speaking-meeting-bot-xxx.a.run.app/ws/hanna-001",
    "streaming_output": "wss://speaking-meeting-bot-xxx.a.run.app/ws/hanna-001",
    "streaming_audio_frequency": 24000
}
EOF

# Run bot when needed
sudo docker run -v /tmp/bot-config.json:/app/bot.config.json \
  gcr.io/$GCP_PROJECT_ID/meet-teams-bot
```

## Option 3: Hybrid (Cloud Run + Local Docker)

Best for cost optimization - run AI on Cloud Run, bot locally.

### Deploy speaking-meeting-bot to Cloud Run

```bash
cd /home/angelica/speaking-meeting-bot
./deploy-cloud-run.sh
```

### Run meet-teams-bot locally

```bash
cd /home/angelica/meet-teams-bot

# Create config pointing to Cloud Run
cat > hanna-bot.config.json << EOF
{
    "id": "hanna-bot",
    "meeting_url": "MEETING_URL_HERE",
    "bot_name": "Hanna",
    "streaming_input": "wss://speaking-meeting-bot-xxx.a.run.app/ws/hanna-001",
    "streaming_output": "wss://speaking-meeting-bot-xxx.a.run.app/ws/hanna-001",
    "streaming_audio_frequency": 24000,
    "enter_message": "Hi! I'm Hanna!"
}
EOF

# Run
sudo ./run_bot.sh run hanna-bot.config.json
```

## Understanding the WebSocket URLs

The format is: `wss://your-domain/ws/{client_id}`

- `client_id` is a unique identifier for each bot session
- Both `streaming_input` and `streaming_output` use the same URL
- speaking-meeting-bot handles bidirectional audio on one WebSocket

## Creating Personas

Edit personas in speaking-meeting-bot:

```bash
cd /home/angelica/speaking-meeting-bot/@personas

# Create Hanna persona
mkdir hanna
cat > hanna/README.md << 'EOF'
# Hanna - Meeting Assistant

## Personality
You are Hanna, a helpful AI meeting assistant. You listen attentively to conversations and provide information when asked.

## Behavior
- Wait to be called by name ("Hanna") before speaking
- Keep responses concise (under 30 seconds)
- Be professional, friendly, and helpful
- If you don't know something, be honest

## Capabilities
- Summarize discussions
- Answer questions about meeting content
- Provide clarifications
- Track action items

## Voice
Use a clear, professional, warm voice.
EOF
```

## Testing the Setup

1. **Start speaking-meeting-bot** (Cloud Run or locally)
2. **Configure meet-teams-bot** with the WebSocket URL
3. **Run meet-teams-bot** with a test meeting URL
4. **Join the meeting** and say "Hanna, what time is it?"
5. **Hanna should respond!**

## Monitoring

### speaking-meeting-bot logs (Cloud Run):
```bash
gcloud run services logs read speaking-meeting-bot --region us-central1
```

### meet-teams-bot logs (Docker):
```bash
sudo docker logs -f $(sudo docker ps | grep meet-teams-bot | awk '{print $1}')
```

## Costs

### Option 1 (Local): $0 infrastructure + API costs
- OpenAI: ~$0.15/hour
- Cartesia: ~$0.05/hour
- Deepgram: ~$0.02/hour
- **Total: ~$0.22/hour**

### Option 2 (All Cloud Run): Not recommended (Chrome needs stable compute)

### Option 3 (Hybrid): ~$0.20/hour infrastructure + API costs
- Cloud Run (speaking-bot): ~$0.10/hour
- Local Docker: Free
- **Total: ~$0.32/hour**

### Option 4 (Compute Engine): ~$0.30/hour infrastructure + API costs
- e2-standard-2 VM: ~$0.07/hour
- Egress: ~$0.03/hour
- **Total: ~$0.32/hour**

## Recommended Setup

**For Development:** Option 1 (Local + ngrok)
**For Production:** Option 3 (Hybrid: Cloud Run + Local Docker)
**For Scale:** Custom GKE setup with auto-scaling

## Next Steps

1. Choose your deployment option
2. Set up API keys
3. Create your Hanna persona
4. Test with a meeting
5. Monitor and iterate!
