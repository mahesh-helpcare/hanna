#!/bin/bash
set -e

echo "🚀 Self-Hosted Speaking Bot Setup"
echo ""

# Check if we're doing local or cloud
echo "Choose deployment mode:"
echo "1) Local test (speaking-bot locally + ngrok)"
echo "2) Hybrid (speaking-bot on Cloud Run + meet-teams-bot locally)"
echo "3) Setup instructions only"
read -p "Enter choice (1-3): " CHOICE

case $CHOICE in
  1)
    echo ""
    echo "📋 Local Test Setup"
    echo ""

    # Check dependencies
    if ! command -v poetry &> /dev/null; then
        echo "❌ Poetry not found. Install it first:"
        echo "   curl -sSL https://install.python-poetry.org | python3 -"
        exit 1
    fi

    if ! command -v ngrok &> /dev/null; then
        echo "❌ ngrok not found. Install it first:"
        echo "   https://ngrok.com/download"
        exit 1
    fi

    # Check API keys
    if [ -z "$OPENAI_API_KEY" ]; then
        read -p "Enter OpenAI API key: " OPENAI_API_KEY
        export OPENAI_API_KEY
    fi

    if [ -z "$CARTESIA_API_KEY" ]; then
        read -p "Enter Cartesia API key: " CARTESIA_API_KEY
        export CARTESIA_API_KEY
    fi

    if [ -z "$DEEPGRAM_API_KEY" ]; then
        read -p "Enter Deepgram API key: " DEEPGRAM_API_KEY
        export DEEPGRAM_API_KEY
    fi

    echo ""
    echo "✅ Starting speaking-meeting-bot..."
    cd /home/angelica/speaking-meeting-bot

    # Install if needed
    if [ ! -d ".venv" ]; then
        echo "📦 Installing dependencies..."
        poetry install
        poetry run python -m grpc_tools.protoc --proto_path=./protobufs --python_out=./protobufs frames.proto
    fi

    export PORT=7014

    echo ""
    echo "🌐 Starting server on port 7014..."
    echo "⚠️  In another terminal, run: ngrok http 7014"
    echo ""

    poetry run uvicorn app:app --host 0.0.0.0 --port 7014
    ;;

  2)
    echo ""
    echo "📋 Hybrid Setup"
    echo ""

    # Get Cloud Run URL
    read -p "Enter your speaking-meeting-bot Cloud Run URL (or press Enter to deploy now): " CLOUD_RUN_URL

    if [ -z "$CLOUD_RUN_URL" ]; then
        echo "🚀 Deploying speaking-meeting-bot to Cloud Run..."
        cd /home/angelica/speaking-meeting-bot

        if [ -z "$GCP_PROJECT_ID" ]; then
            read -p "Enter GCP Project ID: " GCP_PROJECT_ID
            export GCP_PROJECT_ID
        fi

        ./deploy-cloud-run.sh

        CLOUD_RUN_URL=$(gcloud run services describe speaking-meeting-bot \
          --region us-central1 --format 'value(status.url)')
    fi

    echo ""
    echo "✅ speaking-meeting-bot URL: $CLOUD_RUN_URL"
    echo ""

    # Get meeting URL
    read -p "Enter Google Meet URL: " MEETING_URL

    if [ -z "$MEETING_URL" ]; then
        echo "❌ Meeting URL required"
        exit 1
    fi

    # Generate client ID
    CLIENT_ID="hanna-$(date +%s)"

    # Create config
    cd /home/angelica/meet-teams-bot

    echo "📝 Creating bot config..."
    cat > hanna-bot.config.json << EOF
{
    "id": "$CLIENT_ID",
    "meeting_url": "$MEETING_URL",
    "bot_name": "Hanna",
    "streaming_input": "${CLOUD_RUN_URL#https://}/ws/$CLIENT_ID",
    "streaming_output": "${CLOUD_RUN_URL#https://}/ws/$CLIENT_ID",
    "streaming_audio_frequency": 24000,
    "enter_message": "Hi! I'm Hanna, your meeting assistant.",
    "recording_mode": "speaker_view",
    "environ": "local"
}
EOF

    # Convert to wss://
    sed -i "s|${CLOUD_RUN_URL#https://}|wss://${CLOUD_RUN_URL#https://}|g" hanna-bot.config.json

    echo ""
    echo "✅ Config created: hanna-bot.config.json"
    echo ""
    cat hanna-bot.config.json
    echo ""

    read -p "Start meet-teams-bot now? (y/n): " START_BOT

    if [ "$START_BOT" = "y" ]; then
        echo "🤖 Starting meet-teams-bot..."
        sudo ./run_bot.sh run hanna-bot.config.json
    else
        echo ""
        echo "To start manually:"
        echo "  cd /home/angelica/meet-teams-bot"
        echo "  sudo ./run_bot.sh run hanna-bot.config.json"
    fi
    ;;

  3)
    echo ""
    echo "📖 See self-hosted-setup.md for complete instructions"
    echo ""
    cat /home/angelica/self-hosted-setup.md
    ;;

  *)
    echo "❌ Invalid choice"
    exit 1
    ;;
esac
