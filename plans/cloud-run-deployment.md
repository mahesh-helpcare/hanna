# Cloud Run Deployment Guide

## Prerequisites

1. **Google Cloud Account** with billing enabled
2. **gcloud CLI** installed ([Install guide](https://cloud.google.com/sdk/docs/install))
3. **API Keys** for:
   - OpenAI (LLM)
   - Cartesia (TTS) or alternative
   - Deepgram or Gladia (STT)
   - MeetingBaaS (meeting bot platform)

## Quick Deploy

### 1. Set Your GCP Project

```bash
export GCP_PROJECT_ID="your-project-id"
export GCP_REGION="us-central1"  # Optional, defaults to us-central1
```

### 2. Run Deployment Script

```bash
cd /home/angelica/speaking-meeting-bot
./deploy-cloud-run.sh
```

### 3. Configure API Keys

After deployment, set your API keys:

```bash
gcloud run services update speaking-meeting-bot \
  --region us-central1 \
  --set-env-vars \
    OPENAI_API_KEY="sk-..." \
    CARTESIA_API_KEY="..." \
    DEEPGRAM_API_KEY="..." \
    MEETING_BAAS_API_KEY="..."
```

### 4. Get Your Service URL

```bash
gcloud run services describe speaking-meeting-bot \
  --region us-central1 \
  --format 'value(status.url)'
```

## Manual Deployment (Step by Step)

If you prefer manual control:

### 1. Build the Image

```bash
gcloud builds submit --tag gcr.io/YOUR_PROJECT_ID/speaking-meeting-bot
```

### 2. Deploy to Cloud Run

```bash
gcloud run deploy speaking-meeting-bot \
  --image gcr.io/YOUR_PROJECT_ID/speaking-meeting-bot \
  --platform managed \
  --region us-central1 \
  --allow-unauthenticated \
  --min-instances 0 \
  --max-instances 10 \
  --memory 2Gi \
  --cpu 2 \
  --timeout 3600 \
  --set-env-vars "BASE_URL=https://speaking-meeting-bot-xxx.a.run.app" \
  --port 7014
```

## Cloud Run Configuration

### Resource Limits

- **Memory:** 2Gi (can be adjusted based on usage)
- **CPU:** 2 (needed for audio processing)
- **Timeout:** 3600s (1 hour for long meetings)
- **Concurrency:** Default (80 requests per instance)

### Scaling

- **Min instances:** 0 (cost-effective, cold starts possible)
- **Max instances:** 10 (adjust based on expected load)

**Cold Start Considerations:**
- First bot creation may take 10-15 seconds
- Consider min-instances=1 for production if instant response needed

## Cost Estimation

Cloud Run pricing (us-central1):
- **CPU:** $0.00002400 per vCPU-second
- **Memory:** $0.00000250 per GiB-second
- **Requests:** $0.40 per million requests

**Example:** 1-hour meeting with 1 bot:
- CPU: 2 vCPU × 3600s × $0.000024 = ~$0.17
- Memory: 2 GiB × 3600s × $0.0000025 = ~$0.02
- **Total:** ~$0.19/hour/bot

Plus API costs:
- OpenAI: ~$0.10-0.20/hour
- Cartesia: ~$0.05/hour
- Deepgram: ~$0.02/hour
- **Combined:** ~$0.36-0.46/hour/bot

## Testing Your Deployment

### 1. Health Check

```bash
curl https://your-service-url.a.run.app/
```

Expected response:
```json
{"message": "MeetingBaas Bot API is running"}
```

### 2. Create a Bot

```bash
curl -X POST https://your-service-url.a.run.app/run-bots \
  -H "Content-Type: application/json" \
  -d '{
    "meeting_url": "https://meet.google.com/xxx-yyyy-zzz",
    "personas": ["interviewer"],
    "meeting_baas_api_key": "your-api-key",
    "entry_message": "Hello! I am here to help."
  }'
```

### 3. Check Logs

```bash
gcloud run services logs read speaking-meeting-bot \
  --region us-central1 \
  --limit 50
```

## Production Considerations

### Security

1. **Restrict access** if not public:
   ```bash
   gcloud run services update speaking-meeting-bot \
     --region us-central1 \
     --no-allow-unauthenticated
   ```

2. **Use Secret Manager** for API keys:
   ```bash
   # Create secret
   echo -n "sk-..." | gcloud secrets create openai-api-key --data-file=-

   # Mount to Cloud Run
   gcloud run services update speaking-meeting-bot \
     --update-secrets OPENAI_API_KEY=openai-api-key:latest
   ```

### Monitoring

1. **Enable Cloud Monitoring:**
   - Go to Cloud Console → Cloud Run → speaking-meeting-bot → Metrics
   - Set up alerts for error rate, latency, etc.

2. **Custom metrics:**
   - Bot creation success rate
   - WebSocket connection duration
   - Audio processing latency

### Custom Domain (Optional)

```bash
gcloud run domain-mappings create \
  --service speaking-meeting-bot \
  --domain bots.yourdomain.com \
  --region us-central1
```

## Troubleshooting

### WebSocket Connection Issues

Cloud Run fully supports WebSockets, but ensure:
1. `BASE_URL` environment variable is set correctly
2. Client connects via HTTPS/WSS (not HTTP/WS)

### Cold Start Delays

If bots take too long to create:
1. Set `--min-instances 1` to keep at least one warm
2. Optimize Docker image size
3. Consider Cloud Run second generation execution environment

### Memory Issues

If you see OOM errors:
```bash
gcloud run services update speaking-meeting-bot \
  --region us-central1 \
  --memory 4Gi
```

### Bot Not Joining Meeting

Check logs for:
- MeetingBaaS API errors
- WebSocket connection failures
- Audio pipeline initialization issues

## Updating the Service

```bash
# Rebuild and redeploy
gcloud builds submit --tag gcr.io/YOUR_PROJECT_ID/speaking-meeting-bot
gcloud run deploy speaking-meeting-bot --image gcr.io/YOUR_PROJECT_ID/speaking-meeting-bot
```

Or use the deployment script:
```bash
./deploy-cloud-run.sh
```

## Cleanup

To delete the service:
```bash
gcloud run services delete speaking-meeting-bot --region us-central1
```

To delete the image:
```bash
gcloud container images delete gcr.io/YOUR_PROJECT_ID/speaking-meeting-bot
```
