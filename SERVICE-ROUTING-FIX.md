# Service Routing Fix

## Problem
The GPU service was timing out because both the CPU and GPU services had overlapping selectors. The CPU service selector was matching both CPU and GPU pods, causing routing conflicts.

## Root Cause
- **CPU Service** selector: `app=llama-cpp, component=server` (missing `accelerator` label)
- **GPU Service** selector: `app=llama-cpp, component=server, accelerator=gpu`
- **CPU Deployment** pods: `app=llama-cpp, component=server` (missing `accelerator` label)
- **GPU Deployment** pods: `app=llama-cpp, component=server, accelerator=gpu`

This meant the CPU service could match both CPU and GPU pods, causing unpredictable routing.

## Solution Applied
1. Added `accelerator: cpu` label to CPU deployment pods (k8s-manifests/04-deployment-cpu-only.yaml)
2. Added `accelerator: cpu` to CPU service selector (k8s-manifests/05-service.yaml)

## Current State
Both services now have unique, non-overlapping selectors:

```bash
# CPU Service
NAME                    SELECTOR
llama-cpp-service       accelerator=cpu,app=llama-cpp,component=server

# GPU Service  
NAME                    SELECTOR
llama-cpp-service-gpu   accelerator=gpu,app=llama-cpp,component=server
```

## Verification
Services are working correctly from within the cluster:

```bash
# Test GPU service
oc run test-curl --image=curlimages/curl:latest --rm -i --restart=Never -n <your-namespace> \
  -- curl -sS -m 5 http://llama-cpp-service-gpu:8080/v1/models

# Test CPU service
oc run test-curl --image=curlimages/curl:latest --rm -i --restart=Never -n <your-namespace> \
  -- curl -sS -m 5 http://llama-cpp-service:8080/v1/models
```

Both return valid model information.

## External Route Access
If external routes are timing out, this is likely due to:
1. Network connectivity issues from your current location
2. Firewall rules blocking external access
3. VPN requirements for accessing the cluster's external routes

### Testing from Within the Cluster
You can always test the services from within the cluster using:

```bash
# Port-forward to access locally
oc port-forward -n <your-namespace> deployment/llama-cpp-server-gpu 8080:8080

# Then in another terminal
curl http://localhost:8080/v1/models
```

Or use the web UI by port-forwarding:
```bash
oc port-forward -n <your-namespace> deployment/llama-cpp-server-gpu 8080:8080
# Open browser to http://localhost:8080
```

## Routes
- **CPU Route**: https://llama-cpp-route-<your-namespace>.apps.<your-cluster-domain>
- **GPU Route**: https://llama-cpp-route-gpu-<your-namespace>.apps.<your-cluster-domain>

These routes work when accessed from a network that has connectivity to the OpenShift cluster's external ingress.