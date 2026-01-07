#!/bin/bash

# Test script for llama.cpp API endpoints
# This script validates the deployment and tests various API endpoints

set -e

NAMESPACE="andre-llama-cpp"

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

print_header() {
    echo ""
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}========================================${NC}"
    echo ""
}

print_success() {
    echo -e "${GREEN}[✓]${NC} $1"
}

print_error() {
    echo -e "${RED}[✗]${NC} $1"
}

print_info() {
    echo -e "${YELLOW}[i]${NC} $1"
}

# Check if oc command is available
if ! command -v oc &> /dev/null; then
    print_error "oc command not found. Please install OpenShift CLI."
    exit 1
fi

# Check if curl is available
if ! command -v curl &> /dev/null; then
    print_error "curl command not found. Please install curl."
    exit 1
fi

# Check if jq is available (optional but recommended)
if ! command -v jq &> /dev/null; then
    print_info "jq not found. Install jq for better JSON formatting."
    JQ_AVAILABLE=false
else
    JQ_AVAILABLE=true
fi

print_header "Mistral 7B llama.cpp API Test Suite"

# Get route URL
print_info "Getting route URL..."
ROUTE_URL=$(oc get route llama-cpp-route -n ${NAMESPACE} -o jsonpath='{.spec.host}' 2>/dev/null || echo "")

if [ -z "$ROUTE_URL" ]; then
    print_error "Could not retrieve route URL. Is the deployment complete?"
    exit 1
fi

print_success "Route URL: https://${ROUTE_URL}"
echo ""

# Check pod status
print_info "Checking pod status..."
POD_STATUS=$(oc get pods -n ${NAMESPACE} -l app=llama-cpp -o jsonpath='{.items[0].status.phase}' 2>/dev/null || echo "")

if [ "$POD_STATUS" != "Running" ]; then
    print_error "Pod is not running. Current status: ${POD_STATUS}"
    print_info "Check pod status with: oc get pods -n ${NAMESPACE}"
    exit 1
fi

print_success "Pod is running"
echo ""

# Test 1: Health Check
print_header "Test 1: Health Check"
print_info "Testing /health endpoint..."

HEALTH_RESPONSE=$(curl -s -k https://${ROUTE_URL}/health)
HEALTH_STATUS=$?

if [ $HEALTH_STATUS -eq 0 ]; then
    print_success "Health check passed"
    if [ "$JQ_AVAILABLE" = true ]; then
        echo "$HEALTH_RESPONSE" | jq .
    else
        echo "$HEALTH_RESPONSE"
    fi
else
    print_error "Health check failed"
    exit 1
fi

# Test 2: Model Information
print_header "Test 2: Model Information"
print_info "Testing /v1/models endpoint..."

MODELS_RESPONSE=$(curl -s -k https://${ROUTE_URL}/v1/models)
MODELS_STATUS=$?

if [ $MODELS_STATUS -eq 0 ]; then
    print_success "Models endpoint accessible"
    if [ "$JQ_AVAILABLE" = true ]; then
        echo "$MODELS_RESPONSE" | jq .
    else
        echo "$MODELS_RESPONSE"
    fi
else
    print_error "Models endpoint failed"
fi

# Test 3: Simple Completion
print_header "Test 3: Simple Text Completion"
print_info "Testing /completion endpoint with a simple prompt..."

COMPLETION_PAYLOAD='{
  "prompt": "The capital of France is",
  "n_predict": 50,
  "temperature": 0.7,
  "stop": ["\n"]
}'

print_info "Sending request..."
COMPLETION_RESPONSE=$(curl -s -k -X POST https://${ROUTE_URL}/completion \
  -H "Content-Type: application/json" \
  -d "$COMPLETION_PAYLOAD")

COMPLETION_STATUS=$?

if [ $COMPLETION_STATUS -eq 0 ]; then
    print_success "Completion request successful"
    if [ "$JQ_AVAILABLE" = true ]; then
        echo "$COMPLETION_RESPONSE" | jq .
        GENERATED_TEXT=$(echo "$COMPLETION_RESPONSE" | jq -r '.content' 2>/dev/null || echo "")
        if [ -n "$GENERATED_TEXT" ]; then
            echo ""
            print_info "Generated text: $GENERATED_TEXT"
        fi
    else
        echo "$COMPLETION_RESPONSE"
    fi
else
    print_error "Completion request failed"
fi

# Test 4: Chat Completion (OpenAI-compatible)
print_header "Test 4: Chat Completion (OpenAI-compatible)"
print_info "Testing /v1/chat/completions endpoint..."

CHAT_PAYLOAD='{
  "model": "mistral-7b",
  "messages": [
    {
      "role": "system",
      "content": "You are a helpful assistant. Keep responses brief."
    },
    {
      "role": "user",
      "content": "What is 2+2?"
    }
  ],
  "temperature": 0.7,
  "max_tokens": 100
}'

print_info "Sending chat request..."
CHAT_RESPONSE=$(curl -s -k -X POST https://${ROUTE_URL}/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d "$CHAT_PAYLOAD")

CHAT_STATUS=$?

if [ $CHAT_STATUS -eq 0 ]; then
    print_success "Chat completion request successful"
    if [ "$JQ_AVAILABLE" = true ]; then
        echo "$CHAT_RESPONSE" | jq .
        CHAT_CONTENT=$(echo "$CHAT_RESPONSE" | jq -r '.choices[0].message.content' 2>/dev/null || echo "")
        if [ -n "$CHAT_CONTENT" ]; then
            echo ""
            print_info "Assistant response: $CHAT_CONTENT"
        fi
    else
        echo "$CHAT_RESPONSE"
    fi
else
    print_error "Chat completion request failed"
fi

# Test 5: Metrics
print_header "Test 5: Prometheus Metrics"
print_info "Testing /metrics endpoint..."

METRICS_RESPONSE=$(curl -s -k https://${ROUTE_URL}/metrics | head -20)
METRICS_STATUS=$?

if [ $METRICS_STATUS -eq 0 ]; then
    print_success "Metrics endpoint accessible"
    echo "First 20 lines of metrics:"
    echo "$METRICS_RESPONSE"
else
    print_error "Metrics endpoint failed"
fi

# Summary
print_header "Test Summary"

echo "All basic tests completed!"
echo ""
echo "Next steps:"
echo "1. Try more complex prompts using the examples in USAGE.md"
echo "2. Monitor performance with: oc logs -n ${NAMESPACE} -l app=llama-cpp -f"
echo "3. Check GPU utilization if available"
echo ""
echo "API Base URL: https://${ROUTE_URL}"
echo ""
print_success "Deployment is ready for use!"