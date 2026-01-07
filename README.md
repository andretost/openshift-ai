# Mistral 7B Deployment with llama.cpp on OpenShift AI

Deploy and run Mistral 7B large language model using llama.cpp on OpenShift with GPU acceleration.

## Overview

This repository contains everything needed to deploy Mistral 7B Instruct v0.2 on OpenShift using llama.cpp server with GPU support. The deployment includes:

- **Model**: Mistral 7B Instruct v0.2 (GGUF format, Q4_K_M quantization)
- **Runtime**: llama.cpp server with CUDA support
- **Storage**: 30GB PersistentVolumeClaim for model files
- **Namespace**: `andre-llama-cpp`
- **GPU**: NVIDIA GPU acceleration (1 GPU required)
- **API**: OpenAI-compatible REST API

## Architecture

```
┌─────────────────────────────────────────────────────────┐
│                    OpenShift Cluster                     │
│  ┌───────────────────────────────────────────────────┐  │
│  │         Namespace: andre-llama-cpp                │  │
│  │                                                   │  │
│  │  ┌─────────────┐      ┌──────────────────────┐  │  │
│  │  │   Route     │─────▶│      Service         │  │  │
│  │  │  (HTTPS)    │      │   (ClusterIP:8080)   │  │  │
│  │  └─────────────┘      └──────────┬───────────┘  │  │
│  │                                   │              │  │
│  │                       ┌───────────▼───────────┐  │  │
│  │                       │    Pod                │  │  │
│  │                       │  ┌─────────────────┐  │  │  │
│  │                       │  │ Init Container  │  │  │  │
│  │                       │  │ (Model Download)│  │  │  │
│  │                       │  └─────────────────┘  │  │  │
│  │                       │  ┌─────────────────┐  │  │  │
│  │                       │  │ llama.cpp       │  │  │  │
│  │                       │  │ Server (GPU)    │  │  │  │
│  │                       │  └─────────────────┘  │  │  │
│  │                       └───────────┬───────────┘  │  │
│  │                                   │              │  │
│  │                       ┌───────────▼───────────┐  │  │
│  │                       │   PVC (30GB)          │  │  │
│  │                       │   Model Storage       │  │  │
│  │                       └───────────────────────┘  │  │
│  └───────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────┘
```

## Prerequisites

- OpenShift cluster with OpenShift AI 2.25.1 installed
- Access to a namespace (or ability to create one)
- NVIDIA GPU nodes available in the cluster
- OpenShift CLI (`oc`) installed and configured
- Logged in to your OpenShift cluster

## Quick Start

### 1. Clone or Download This Repository

```bash
git clone <repository-url>
cd openshift-ai
```

### 2. Review Configuration

Check the ConfigMap settings in `k8s-manifests/03-configmap.yaml` and adjust if needed:
- GPU layers to offload
- Context window size
- Number of parallel requests
- Model parameters (temperature, top_k, etc.)

### 3. Deploy

Run the deployment script:

```bash
./deploy.sh
```

This script will:
1. Create the namespace `andre-llama-cpp`
2. Create a 30GB PVC for model storage
3. Deploy the ConfigMap with server settings
4. Deploy the pod with init container (downloads ~4GB model)
5. Create the Service and Route for API access

### 4. Monitor Deployment

Watch the deployment progress:

```bash
# Watch pod status
oc get pods -n andre-llama-cpp -w

# Monitor model download (init container)
oc logs -n andre-llama-cpp -l app=llama-cpp -c model-downloader -f

# Monitor server startup
oc logs -n andre-llama-cpp -l app=llama-cpp -c llama-cpp-server -f
```

The model download takes 5-15 minutes depending on network speed. The server will start automatically once the model is downloaded.

### 5. Test the Deployment

Once the pod is running, test the API:

```bash
./test-api.sh
```

This script tests:
- Health endpoint
- Model information
- Text completion
- Chat completion (OpenAI-compatible)
- Metrics endpoint

## Usage

### Get API URL

```bash
ROUTE_URL=$(oc get route llama-cpp-route -n andre-llama-cpp -o jsonpath='{.spec.host}')
echo "API URL: https://${ROUTE_URL}"
```

### Simple Text Completion

```bash
curl -X POST https://${ROUTE_URL}/completion \
  -H "Content-Type: application/json" \
  -d '{
    "prompt": "Explain quantum computing:",
    "n_predict": 200
  }'
```

### Chat Completion (OpenAI-compatible)

```bash
curl -X POST https://${ROUTE_URL}/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "mistral-7b",
    "messages": [
      {"role": "user", "content": "What is machine learning?"}
    ]
  }'
```

### Python Example

```python
from openai import OpenAI

client = OpenAI(
    base_url=f"https://{ROUTE_URL}/v1",
    api_key="not-needed"
)

response = client.chat.completions.create(
    model="mistral-7b",
    messages=[
        {"role": "user", "content": "Hello!"}
    ]
)

print(response.choices[0].message.content)
```

For more examples and detailed usage instructions, see [USAGE.md](USAGE.md).

## Files and Structure

```
.
├── README.md                    # This file
├── deployment-plan.md           # Detailed deployment architecture
├── USAGE.md                     # Comprehensive usage guide
├── deploy.sh                    # Automated deployment script
├── test-api.sh                  # API testing script
└── k8s-manifests/              # Kubernetes manifests
    ├── 01-namespace.yaml        # Namespace definition
    ├── 02-pvc.yaml             # PersistentVolumeClaim (30GB)
    ├── 03-configmap.yaml       # Server configuration
    ├── 04-deployment.yaml      # Main deployment with init container
    ├── 05-service.yaml         # Service (ClusterIP)
    └── 06-route.yaml           # Route (external access)
```

## Configuration

### Model Selection

To use a different model or quantization:

1. Edit `k8s-manifests/03-configmap.yaml`
2. Update `HF_REPO` and `HF_MODEL_FILE`
3. Adjust `MODEL_PATH` accordingly
4. Redeploy: `oc apply -f k8s-manifests/03-configmap.yaml`
5. Restart: `oc rollout restart deployment llama-cpp-server -n andre-llama-cpp`

### GPU Configuration

The deployment requests 1 NVIDIA GPU. To adjust:

1. Edit `k8s-manifests/04-deployment.yaml`
2. Modify `nvidia.com/gpu` in resources section
3. Adjust `N_GPU_LAYERS` in ConfigMap (35 = all layers on GPU)

### Resource Limits

Default resources:
- **CPU**: 4 cores (request), 8 cores (limit)
- **Memory**: 16Gi (request), 24Gi (limit)
- **GPU**: 1x NVIDIA GPU
- **Storage**: 30GB PVC

Adjust in `k8s-manifests/04-deployment.yaml` based on your needs.

## Troubleshooting

### Pod Not Starting

```bash
# Check pod status and events
oc describe pod -n andre-llama-cpp -l app=llama-cpp

# Check events
oc get events -n andre-llama-cpp --sort-by='.lastTimestamp'
```

### Model Download Failed

```bash
# Check init container logs
oc logs -n andre-llama-cpp -l app=llama-cpp -c model-downloader

# Delete pod to retry
oc delete pod -n andre-llama-cpp -l app=llama-cpp
```

### GPU Not Available

```bash
# Check GPU nodes
oc describe node | grep -A 5 "nvidia.com/gpu"

# Verify node selector matches your cluster
oc get nodes --show-labels | grep gpu
```

### API Not Responding

```bash
# Check server logs
oc logs -n andre-llama-cpp -l app=llama-cpp -c llama-cpp-server

# Check service and route
oc get svc,route -n andre-llama-cpp
```

## Performance Tuning

### For Higher Throughput

Increase parallel requests in ConfigMap:
```yaml
N_PARALLEL: "8"  # Default: 4
```

### For Lower Latency

Reduce context size:
```yaml
N_CTX: "4096"  # Default: 8192
```

### For Lower Memory Usage

Use a smaller quantization (edit ConfigMap):
```yaml
HF_MODEL_FILE: "mistral-7b-instruct-v0.2.Q3_K_M.gguf"  # Smaller than Q4
```

## Cleanup

To remove the deployment:

```bash
# Delete entire namespace
oc delete namespace andre-llama-cpp

# Or delete individual resources
oc delete -f k8s-manifests/ -n andre-llama-cpp
```

## API Endpoints

- `GET /health` - Health check
- `POST /completion` - Text completion
- `POST /v1/chat/completions` - Chat completion (OpenAI-compatible)
- `GET /v1/models` - List models
- `GET /metrics` - Prometheus metrics

See [USAGE.md](USAGE.md) for detailed API documentation.

## Resources

- [llama.cpp GitHub](https://github.com/ggerganov/llama.cpp)
- [Mistral AI Documentation](https://docs.mistral.ai/)
- [OpenShift AI Documentation](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/)
- [GGUF Format Documentation](https://github.com/ggerganov/ggml/blob/master/docs/gguf.md)

## License

This deployment configuration is provided as-is. Please refer to the licenses of the individual components:
- llama.cpp: MIT License
- Mistral 7B: Apache 2.0 License

## Support

For issues:
- **Deployment issues**: Check the troubleshooting section above
- **llama.cpp issues**: [llama.cpp GitHub Issues](https://github.com/ggerganov/llama.cpp/issues)
- **OpenShift issues**: Consult your cluster administrator
- **Model behavior**: [Mistral AI Documentation](https://docs.mistral.ai/)