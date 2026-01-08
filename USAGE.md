# Mistral 7B with llama.cpp - Usage Guide

## Overview

This guide explains how to interact with your deployed Mistral 7B model running on llama.cpp in OpenShift.

## Prerequisites

- Deployment completed successfully
- Pod is in `Running` state
- Route is accessible

## Getting Started

### 1. Check Deployment Status

```bash
# Check pod status
oc get pods -n <your-namespace>

# Watch pod startup (especially useful during model download)
oc get pods -n <your-namespace> -w

# Check init container logs (model download)
oc logs -n <your-namespace> -l app=llama-cpp -c model-downloader -f

# Check main container logs
oc logs -n <your-namespace> -l app=llama-cpp -c llama-cpp-server -f
```

### 2. Get Route URL

```bash
# Get the external URL
ROUTE_URL=$(oc get route llama-cpp-route -n <your-namespace> -o jsonpath='{.spec.host}')
echo "API URL: https://${ROUTE_URL}"
```

### 3. Test Health Endpoint

```bash
curl https://${ROUTE_URL}/health
```

Expected response:
```json
{
  "status": "ok"
}
```

## API Endpoints

### 1. Text Completion

Generate text completions using the `/completion` endpoint.

**Example:**

```bash
curl -X POST https://${ROUTE_URL}/completion \
  -H "Content-Type: application/json" \
  -d '{
    "prompt": "Explain quantum computing in simple terms:",
    "n_predict": 200,
    "temperature": 0.7,
    "top_k": 40,
    "top_p": 0.9,
    "repeat_penalty": 1.1
  }'
```

**Parameters:**
- `prompt`: The input text to complete
- `n_predict`: Maximum number of tokens to generate (default: 128)
- `temperature`: Randomness (0.0-2.0, default: 0.7)
- `top_k`: Top-K sampling (default: 40)
- `top_p`: Top-P sampling (default: 0.9)
- `repeat_penalty`: Penalty for repeating tokens (default: 1.1)
- `stop`: Array of stop sequences

### 2. Chat Completions (OpenAI-Compatible)

Use the OpenAI-compatible chat endpoint for conversational interactions.

**Example:**

```bash
curl -X POST https://${ROUTE_URL}/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "mistral-7b",
    "messages": [
      {
        "role": "system",
        "content": "You are a helpful AI assistant."
      },
      {
        "role": "user",
        "content": "What is the capital of France?"
      }
    ],
    "temperature": 0.7,
    "max_tokens": 200
  }'
```

**Response:**

```json
{
  "id": "chatcmpl-123",
  "object": "chat.completion",
  "created": 1234567890,
  "model": "mistral-7b",
  "choices": [
    {
      "index": 0,
      "message": {
        "role": "assistant",
        "content": "The capital of France is Paris..."
      },
      "finish_reason": "stop"
    }
  ],
  "usage": {
    "prompt_tokens": 20,
    "completion_tokens": 50,
    "total_tokens": 70
  }
}
```

### 3. Streaming Responses

For real-time token generation, use streaming:

```bash
curl -X POST https://${ROUTE_URL}/completion \
  -H "Content-Type: application/json" \
  -d '{
    "prompt": "Write a short story about a robot:",
    "n_predict": 500,
    "stream": true
  }' \
  --no-buffer
```

### 4. Model Information

Get information about the loaded model:

```bash
curl https://${ROUTE_URL}/v1/models
```

### 5. Metrics

View Prometheus-compatible metrics:

```bash
curl https://${ROUTE_URL}/metrics
```

## Python Examples

### Using requests library

```python
import requests
import json

ROUTE_URL = "https://your-route-url"  # Replace with your route

def chat_completion(messages, temperature=0.7, max_tokens=200):
    """Send a chat completion request."""
    response = requests.post(
        f"{ROUTE_URL}/v1/chat/completions",
        json={
            "model": "mistral-7b",
            "messages": messages,
            "temperature": temperature,
            "max_tokens": max_tokens
        },
        verify=True  # Set to False if using self-signed certs
    )
    return response.json()

# Example usage
messages = [
    {"role": "system", "content": "You are a helpful assistant."},
    {"role": "user", "content": "Explain machine learning in simple terms."}
]

result = chat_completion(messages)
print(result["choices"][0]["message"]["content"])
```

### Using OpenAI Python library

The API is compatible with OpenAI's Python library:

```python
from openai import OpenAI

# Initialize client with your route URL
client = OpenAI(
    base_url=f"https://{ROUTE_URL}/v1",
    api_key="not-needed"  # llama.cpp doesn't require API key
)

# Chat completion
response = client.chat.completions.create(
    model="mistral-7b",
    messages=[
        {"role": "system", "content": "You are a helpful assistant."},
        {"role": "user", "content": "What is Python?"}
    ],
    temperature=0.7,
    max_tokens=200
)

print(response.choices[0].message.content)
```

### Streaming example

```python
from openai import OpenAI

client = OpenAI(
    base_url=f"https://{ROUTE_URL}/v1",
    api_key="not-needed"
)

stream = client.chat.completions.create(
    model="mistral-7b",
    messages=[
        {"role": "user", "content": "Write a poem about AI"}
    ],
    stream=True
)

for chunk in stream:
    if chunk.choices[0].delta.content:
        print(chunk.choices[0].delta.content, end="", flush=True)
```

## Advanced Usage

### Adjusting Model Parameters

You can modify the ConfigMap to change default parameters:

```bash
oc edit configmap llama-cpp-config -n <your-namespace>
```

After editing, restart the deployment:

```bash
oc rollout restart deployment llama-cpp-server -n <your-namespace>
```

### Monitoring GPU Usage

Check GPU utilization:

```bash
# Get pod name
POD_NAME=$(oc get pods -n <your-namespace> -l app=llama-cpp -o jsonpath='{.items[0].metadata.name}')

# Check GPU usage (if nvidia-smi is available in the container)
oc exec -n <your-namespace> ${POD_NAME} -- nvidia-smi
```

### Viewing Logs

```bash
# Follow logs in real-time
oc logs -n <your-namespace> -l app=llama-cpp -c llama-cpp-server -f

# View last 100 lines
oc logs -n <your-namespace> -l app=llama-cpp -c llama-cpp-server --tail=100

# View logs from init container (model download)
oc logs -n <your-namespace> -l app=llama-cpp -c model-downloader
```

### Scaling

The deployment is set to 1 replica by default. To scale:

```bash
# Scale up (not recommended for GPU workloads unless you have multiple GPUs)
oc scale deployment llama-cpp-server -n <your-namespace> --replicas=2

# Scale down
oc scale deployment llama-cpp-server -n <your-namespace> --replicas=0
```

## Troubleshooting

### Pod Not Starting

Check events:
```bash
oc get events -n <your-namespace> --sort-by='.lastTimestamp'
```

Check pod description:
```bash
oc describe pod -n <your-namespace> -l app=llama-cpp
```

### Model Download Issues

If the init container fails to download the model:

```bash
# Check init container logs
oc logs -n <your-namespace> -l app=llama-cpp -c model-downloader

# Delete the pod to retry
oc delete pod -n <your-namespace> -l app=llama-cpp
```

### GPU Not Available

Check if GPU is detected:
```bash
oc describe node | grep -A 5 "nvidia.com/gpu"
```

Verify node selector and tolerations in the deployment match your cluster's GPU node labels.

### Out of Memory

If you encounter OOM errors, you may need to:
1. Use a smaller quantization (e.g., Q3 instead of Q4)
2. Reduce context size in ConfigMap
3. Increase memory limits in deployment

### Connection Timeout

For long-running inference, ensure the route timeout is sufficient:
```bash
oc annotate route llama-cpp-route -n <your-namespace> \
  haproxy.router.openshift.io/timeout=3h --overwrite
```

## Performance Tuning

### Optimize for Throughput

Edit ConfigMap to increase parallel requests:
```yaml
N_PARALLEL: "8"  # Increase from 4
```

### Optimize for Latency

Reduce context size and parallel requests:
```yaml
N_CTX: "4096"     # Reduce from 8192
N_PARALLEL: "1"   # Reduce from 4
```

### GPU Memory Optimization

Adjust GPU layers based on available VRAM:
```yaml
N_GPU_LAYERS: "35"  # All layers on GPU (requires ~8GB VRAM)
N_GPU_LAYERS: "20"  # Partial offload (requires ~4GB VRAM)
```

## Cleanup

To remove the deployment:

```bash
# Delete all resources
oc delete namespace <your-namespace>

# Or delete individual resources
oc delete -f k8s-manifests/ -n <your-namespace>
```

## Additional Resources

- [llama.cpp Documentation](https://github.com/ggerganov/llama.cpp)
- [Mistral AI Documentation](https://docs.mistral.ai/)
- [OpenShift AI Documentation](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/)
- [GGUF Model Format](https://github.com/ggerganov/ggml/blob/master/docs/gguf.md)

## Support

For issues specific to:
- **llama.cpp**: Check the [llama.cpp GitHub issues](https://github.com/ggerganov/llama.cpp/issues)
- **OpenShift**: Consult your cluster administrator
- **Model behavior**: Refer to [Mistral AI documentation](https://docs.mistral.ai/)