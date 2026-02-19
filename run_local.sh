#!/bin/bash

# Kill any existing processes on these ports
echo "Stopping any existing processes on ports 8000-8004..."
if command -v lsof >/dev/null 2>&1; then
    lsof -ti:8000,8001,8002,8003,8004 | xargs kill -9 2>/dev/null
else
    echo "lsof not found, skipping port cleanup. Please ensure ports 8000-8004 are free."
fi

# Ensure uv is in PATH
if ! command -v uv >/dev/null 2>&1; then
    if [ -f "$HOME/.local/bin/env" ]; then
        source "$HOME/.local/bin/env"
    fi
fi
if ! command -v uv >/dev/null 2>&1; then
    echo "Error: 'uv' is not installed or not in PATH. Please install it with: curl -LsSf https://astral.sh/uv/install.sh | sh"
    exit 1
fi

# Load variables from .env if it exists
if [ -f .env ]; then
    echo "Loading environment variables from .env..."
    set -a
    source .env
    set +a
else
    echo "Warning: .env file not found. Attempting to use active gcloud configuration and defaults."
fi

# Set common environment variables for local development
# Detect OS and adjust gcloud command
if [[ "$OSTYPE" == "msys" || "$OSTYPE" == "win32" ]]; then
    GCLOUD_CMD="gcloud.cmd"
else
    GCLOUD_CMD="gcloud"
fi

# Always prioritize the ACTIVE gcloud project for local runs
CURRENT_PROJECT=$($GCLOUD_CMD config get-value project)
if [[ -n "$CURRENT_PROJECT" && "$CURRENT_PROJECT" != "(unset)" ]]; then
    export GOOGLE_CLOUD_PROJECT=$CURRENT_PROJECT
    echo "Using active gcloud project: $GOOGLE_CLOUD_PROJECT"
else
    echo "Warning: No active gcloud project found. Using value from .env if available."
fi

export GOOGLE_CLOUD_LOCATION="us-central1"

# Check if TEMPLATE_NAME belongs to a different project
if [[ -n "$TEMPLATE_NAME" && "$TEMPLATE_NAME" != *"$GOOGLE_CLOUD_PROJECT"* ]]; then
    echo "WARNING: TEMPLATE_NAME in .env ($TEMPLATE_NAME) does not match the active project ($GOOGLE_CLOUD_PROJECT)."
    echo "You might need to re-run ./deploy.sh to update the .env file with the correct template for this project."
    echo "Or update .env manually."
fi
# Set default TEMPLATE_NAME if not set
if [[ -z "$TEMPLATE_NAME" ]]; then
    TEMPLATE_NAME="projects/$GOOGLE_CLOUD_PROJECT/locations/$GOOGLE_CLOUD_LOCATION/templates/course-creator-security-policy"
    echo "TEMPLATE_NAME not set in .env. Using default: $TEMPLATE_NAME"
fi

# Fallback: Try to copy from starter project if .env is missing
if [[ ! -f .env ]]; then
    STARTER_ENV="../prai-roadshow-lab-3-starter/.env"
    if [ -f "$STARTER_ENV" ]; then
        echo "Attempting to copy .env from starter project ($STARTER_ENV)..."
        cp "$STARTER_ENV" .env
        echo "Reloading .env..."
        set -a
        source .env
        set +a
    fi
fi

# Final validation
if [[ -z "$TEMPLATE_NAME" || "$TEMPLATE_NAME" == "projects//locations/us-central1/templates/course-creator-security-policy" ]]; then
     echo "Error: Could not determine TEMPLATE_NAME and GOOGLE_CLOUD_PROJECT is likely unset."
     echo "Please run 'gcloud config set project <your-project-id>' or create a .env file with TEMPLATE_NAME set."
     exit 1
fi
export GOOGLE_GENAI_USE_VERTEXAI="True" # Use Gemini API locally
export GOOGLE_API_KEY="<your-key-here>" # Use if not using Vertex AI

echo "Using Model Armor Template: ${TEMPLATE_NAME}"
echo "Starting Researcher Agent on port 8001..."
pushd agents/researcher
uv run adk_app.py --host 0.0.0.0 --port 8001 --a2a . &
RESEARCHER_PID=$!
popd

echo "Starting Judge Agent on port 8002..."
pushd agents/judge
uv run adk_app.py --host 0.0.0.0 --port 8002 --a2a . &
JUDGE_PID=$!
popd

echo "Starting Content Builder Agent on port 8003..."
pushd agents/content_builder
uv run adk_app.py --host 0.0.0.0 --port 8003 --a2a . &
CONTENT_BUILDER_PID=$!
popd

export RESEARCHER_AGENT_CARD_URL=http://localhost:8001/a2a/agent/.well-known/agent-card.json
export JUDGE_AGENT_CARD_URL=http://localhost:8002/a2a/agent/.well-known/agent-card.json
export CONTENT_BUILDER_AGENT_CARD_URL=http://localhost:8003/a2a/agent/.well-known/agent-card.json

echo "Starting Orchestrator Agent on port 8004..."
pushd agents/orchestrator
uv run adk_app.py --host 0.0.0.0 --port 8004 . &
ORCHESTRATOR_PID=$!
popd

# Wait a bit for them to start up
sleep 5

echo "Starting Orchestrator Agent on port 8000..."
pushd app
export AGENT_SERVER_URL=http://localhost:8004

uv run uvicorn main:app --host 0.0.0.0 --port 8000 --reload &
BACKEND_PID=$!
popd

echo "All agents started!"
echo "Researcher: http://localhost:8001"
echo "Judge: http://localhost:8002"
echo "Content Builder: http://localhost:8003"
echo "Orchestrator: http://localhost:8004"
echo "App Server (Frontend): http://localhost:8000"
echo ""
echo "Press Ctrl+C to stop all agents."

# Wait for all processes
trap "kill $RESEARCHER_PID $JUDGE_PID $CONTENT_BUILDER_PID $ORCHESTRATOR_PID $BACKEND_PID; exit" INT
wait
