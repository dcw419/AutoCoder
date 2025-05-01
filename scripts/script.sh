#!/bin/bash

set -e
set -x

# Arguments from workflow
GITHUB_TOKEN="$1"
REPOSITORY="$2"
ISSUE_NUMBER="$3"
OPENAI_API_KEY="$4"  # This can be DeepSeek's key

# Check required arguments
if [ -z "$GITHUB_TOKEN" ] || [ -z "$REPOSITORY" ] || [ -z "$ISSUE_NUMBER" ] || [ -z "$OPENAI_API_KEY" ]; then
  echo "Error: Missing required environment variables."
  exit 1
fi

# Function to fetch issue
fetch_issue_details() {
  curl -s -H "Authorization: token $GITHUB_TOKEN" \
       "https://api.github.com/repos/$REPOSITORY/issues/$ISSUE_NUMBER"
}

# Function to call DeepSeek API
send_prompt_to_deepseek() {
  curl -s -X POST "https://api.deepseek.com/v1/chat/completions" \
    -H "Authorization: Bearer $OPENAI_API_KEY" \
    -H "Content-Type: application/json" \
    -d "{\"model\": \"deepseek-chat\", \"messages\": $MESSAGES_JSON, \"max_tokens\": 500}"
}

# Function to save code
save_to_file() {
  local filename="autocoder-bot/$1"
  local code_snippet="$2"
  mkdir -p "$(dirname "$filename")"
  echo -e "$code_snippet" > "$filename"
  echo "Saved file: $filename"
}

# Get issue body
RESPONSE=$(fetch_issue_details)
ERROR_MESSAGE=$(echo "$RESPONSE" | jq -r '.message // empty')
if [[ "$ERROR_MESSAGE" == "Not Found" ]]; then
  echo "Error: Repository or issue not found!"
  exit 1
fi

ISSUE_BODY=$(echo "$RESPONSE" | jq -r .body)
if [[ -z "$ISSUE_BODY" || "$ISSUE_BODY" == "null" ]]; then
  echo "Error: Issue body is empty or not found."
  exit 1
fi

# Prepare prompt
INSTRUCTIONS="Based on the description below, generate a JSON object where the keys are file paths and the values are code snippets for a production-ready application. Return valid JSON only."
FULL_PROMPT="$INSTRUCTIONS\n\n$ISSUE_BODY"
MESSAGES_JSON=$(jq -n --arg body "$FULL_PROMPT" '[{"role": "user", "content": $body}]')

# Call DeepSeek
RESPONSE=$(send_prompt_to_deepseek)
if [[ -z "$RESPONSE" ]]; then
  echo "Error: No response from DeepSeek API."
  exit 1
fi

RAW_CONTENT=$(echo "$RESPONSE" | jq -r '.choices[0].message.content')
CLEANED_CONTENT=$(echo "$RAW_CONTENT" | sed -e 's/^```json//' -e 's/^```//' -e 's/```$//')

FILES_JSON=$(echo "$CLEANED_CONTENT" | jq -e '.' 2>/dev/null)
if [[ -z "$FILES_JSON" ]]; then
  echo "Error: No valid JSON found in DeepSeek response."
  exit 1
fi

for key in $(echo "$FILES_JSON" | jq -r 'keys[]'); do
  FILENAME="$key"
  CODE_SNIPPET=$(echo "$FILES_JSON" | jq -r --arg key "$key" '.[$key]')
  CODE_SNIPPET=$(echo "$CODE_SNIPPET" | sed 's/\r$//')
  save_to_file "$FILENAME" "$CODE_SNIPPET"
done

echo "All files generated successfully."
