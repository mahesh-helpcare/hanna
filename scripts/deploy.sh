#!/bin/bash
set -e

# Configuration
PROJECT_ID="${GCP_PROJECT_ID:-your-gcp-project-id}"
SERVICE_NAME="speaking-meeting-bot"
REGION="${GCP_REGION:-us-central1}"
IMAGE_NAME="gcr.io/${PROJECT_ID}/${SERVICE_NAME}"

echo "🚀 Deploying Speaking Meeting Bot to Cloud Run"
echo "Project: $PROJECT_ID"
echo "Region: $REGION"
echo ""

# Check if gcloud is installed
if ! command -v gcloud &> /dev/null; then
    echo "❌ gcloud CLI not found. Please install it first:"
    echo "   https://cloud.google.com/sdk/docs/install"
    exit 1
fi

# Set project
echo "📦 Setting GCP project..."
gcloud config set project $PROJECT_ID

# Build and push the image
echo "🔨 Building Docker image..."
gcloud builds submit --tag $IMAGE_NAME

# Deploy to Cloud Run
echo "☁️  Deploying to Cloud Run..."
gcloud run deploy $SERVICE_NAME \
  --image $IMAGE_NAME \
  --platform managed \
  --region $REGION \
  --allow-unauthenticated \
  --min-instances 0 \
  --max-instances 10 \
  --memory 2Gi \
  --cpu 2 \
  --timeout 3600 \
  --set-env-vars "BASE_URL=https://${SERVICE_NAME}-${PROJECT_ID}.a.run.app" \
  --port 7014

echo ""
echo "✅ Deployment complete!"
echo ""
echo "📝 Next steps:"
echo "1. Set your API keys as environment variables:"
echo "   gcloud run services update $SERVICE_NAME --region $REGION \\"
echo "     --set-env-vars OPENAI_API_KEY=sk-... \\"
echo "     --set-env-vars CARTESIA_API_KEY=... \\"
echo "     --set-env-vars DEEPGRAM_API_KEY=... \\"
echo "     --set-env-vars MEETING_BAAS_API_KEY=..."
echo ""
echo "2. Get your service URL:"
echo "   gcloud run services describe $SERVICE_NAME --region $REGION --format 'value(status.url)'"
