#!/bin/bash
# Generate flow diagram SVGs from the Mermaid source in the README.
# Requires: @mermaid-js/mermaid-cli (npm install -g @mermaid-js/mermaid-cli)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
OUT_DIR="$SCRIPT_DIR/public"
TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT

# Extract the mermaid block from the README
MERMAID_LR=$(sed -n '/^```mermaid$/,/^```$/{ /^```/d; p; }' "$ROOT_DIR/README.md")

if [ -z "$MERMAID_LR" ]; then
  echo "Error: no mermaid block found in README.md" >&2
  exit 1
fi

# Desktop: flowchart LR (as in README)
echo "$MERMAID_LR" > "$TMP_DIR/flow.mmd"

# Mobile: flowchart TD (top-down)
echo "$MERMAID_LR" | sed 's/^flowchart LR/flowchart TD/' > "$TMP_DIR/flow-mobile.mmd"

# Mermaid config: dark theme to match the app
cat > "$TMP_DIR/config.json" <<'EOF'
{
  "theme": "dark",
  "themeVariables": {
    "darkMode": true,
    "background": "#1a1d27",
    "primaryColor": "#2a2d3a",
    "primaryTextColor": "#e1e4ed",
    "primaryBorderColor": "#3a4a7a",
    "lineColor": "#6c8cff",
    "secondaryColor": "#22252f",
    "tertiaryColor": "#22252f",
    "edgeLabelBackground": "#1a1d27"
  }
}
EOF

echo "Generating flow.svg (desktop, LR)..."
mmdc -i "$TMP_DIR/flow.mmd" -o "$OUT_DIR/flow.svg" -c "$TMP_DIR/config.json" -b transparent

echo "Generating flow-mobile.svg (mobile, TD)..."
mmdc -i "$TMP_DIR/flow-mobile.mmd" -o "$OUT_DIR/flow-mobile.svg" -c "$TMP_DIR/config.json" -b transparent

echo "Done: $OUT_DIR/flow.svg, $OUT_DIR/flow-mobile.svg"
