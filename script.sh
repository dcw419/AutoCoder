#!/bin/bash

# Exit immediately if a command exits with a non-zero status.
set -e
# Print each command before executing
set -x

# Get inputs from environment (passed as arguments)
GITHUB_TOKEN="$1"
REPOSITORY="$2"
ISSUE_NUMBER="$3"
DEEPSEEK_API_KEY="$4"

# Check if required arguments are provided
if [ -z "$GITHUB_TOKEN" ] || [ -z "$REPOSITORY" ] || [ -z "$ISSUE_NUMBER" ] || [ -z "$DEEPSEEK_API_KEY" ]; then
  echo "Error: Missing required environment variables."
  exit 1
fi

# Function to fetch issue details from GitHub API
fetch_issue_details() {
  curl -s -H "Authorization: token $GITHUB_TOKEN" \
       "https://api.github.com/repos/$REPOSITORY/issues/$ISSUE_NUMBER"
}

# Function to send prompt to the DeepSeek model API
send_prompt_to_deepseek() {
  curl -s -X POST "https://api.deepseek.com/v1/chat/completions" \
    -H "Authorization: Bearer $DEEPSEEK_API_KEY" \
    -H "Content-Type: application/json" \
    -d "{\"model\": \"deepseek-chat\", \"messages\": $MESSAGES_JSON, \"max_tokens\": 500}"
}

# Function to save code snippet to file
save_to_file() {
  local filename="autocoder-bot/$1"
  local code_snippet="$2"

  mkdir -p "$(dirname "$filename")"
  echo -e "$code_snippet" > "$filename"
  echo "The code has been written to $filename"
}

# Fetch and process issue details
RESPONSE=$(fetch_issue_details)
ISSUE_BODY=$(echo "$RESPONSE" | jq -r .body)

if [[ -z "$ISSUE_BODY" ]]; then
  echo "Error: Issue body is empty or not found."
  exit 1
fi

# Prepare instructions for the model
INSTRUCTIONS="Based on the description below, please generate a JSON object where the keys represent file paths and the values are the corresponding code snippets for a production-ready application. The response should be a valid strictly JSON object without any additional formatting, markdown, or characters outside the JSON structure."

# Combine instructions and issue body
FULL_PROMPT="$INSTRUCTIONS\n\n$ISSUE_BODY"

# Format messages array
MESSAGES_JSON=$(jq -n --arg body "$FULL_PROMPT" '[{"role": "user", "content": $body}]')

# Send prompt to DeepSeek
RESPONSE=$(send_prompt_to_deepseek)

if [[ -z "$RESPONSE" ]]; then
  echo "Error: No response from DeepSeek API."
  exit 1
fi

# Extract and clean the response
RAW_CONTENT=$(echo "$RESPONSE" | jq -r '.choices[0].message.content')
CLEANED_CONTENT=$(echo "$RAW_CONTENT" | sed -e 's/^```json//' -e 's/^```//' -e 's/```$//')

# Parse JSON
FILES_JSON=$(echo "$CLEANED_CONTENT" | jq -e '.' 2>/dev/null)

if [[ -z "$FILES_JSON" ]]; then
  echo "Error: No valid JSON found in DeepSeek response."
  exit 1
fi

# Iterate and save files
for key in $(echo "$FILES_JSON" | jq -r 'keys[]'); do
  FILENAME="$key"
  CODE_SNIPPET=$(echo "$FILES_JSON" | jq -r --arg key "$key" '.[$key]')
  CODE_SNIPPET=$(echo "$CODE_SNIPPET" | sed 's/\r$//')  # Normalize line endings
  save_to_file "$FILENAME" "$CODE_SNIPPET"
done

echo "All files have been processed successfully."
