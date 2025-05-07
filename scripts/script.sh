#!/bin/bash

set -e
set -x

GITHUB_TOKEN="$1"
REPOSITORY="$2"
ISSUE_NUMBER="$3"
DEEPSEEK_API_KEY="$4"

if [ -z "$GITHUB_TOKEN" ] || [ -z "$REPOSITORY" ] || [ -z "$ISSUE_NUMBER" ] || [ -z "$DEEPSEEK_API_KEY" ]; then
  echo "❌ Missing required environment variables."
  exit 1
fi

fetch_issue_details() {
  curl -s -H "Authorization: token $GITHUB_TOKEN" \
       "https://api.github.com/repos/$REPOSITORY/issues/$ISSUE_NUMBER"
}

send_prompt_to_deepseek() {
  curl -s -X POST "https://api.deepseek.com/v1/chat/completions" \
    -H "Authorization: Bearer $DEEPSEEK_API_KEY" \
    -H "Content-Type: application/json" \
    -d "{\"model\": \"deepseek-chat\", \"messages\": $MESSAGES_JSON, \"max_tokens\": 500}"
}

save_to_file() {
  local filename="autocoder-bot/$1"
  local code_snippet="$2"
  mkdir -p "$(dirname "$filename")"
  echo -e "$code_snippet" > "$filename"
  echo "💾 Saved file: $filename"
}

RESPONSE=$(fetch_issue_details)
ERROR_MESSAGE=$(echo "$RESPONSE" | jq -r '.message // empty')
if [[ "$ERROR_MESSAGE" == "Not Found" ]]; then
  echo "❌ GitHub API: Repository or issue not found!"
  exit 1
fi

ISSUE_BODY=$(echo "$RESPONSE" | jq -r .body)
if [[ -z "$ISSUE_BODY" || "$ISSUE_BODY" == "null" ]]; then
  echo "❌ GitHub Issue body is empty or missing."
  exit 1
fi

INSTRUCTIONS="Based on the description below, generate a JSON object where the keys are file paths and the values are code snippets. Return only valid JSON."
FULL_PROMPT="$INSTRUCTIONS\n\n$ISSUE_BODY"
MESSAGES_JSON=$(jq -n --arg body "$FULL_PROMPT" '[{ "role": "user", "content": $body }]')

RESPONSE=$(send_prompt_to_deepseek)

API_ERROR=$(echo "$RESPONSE" | jq -r '.error.message // empty')
if [[ -n "$API_ERROR" ]]; then
  echo "❌ DeepSeek API error: $API_ERROR"
  exit 1
fi

RAW_CONTENT=$(echo "$RESPONSE" | jq -r '.choices[0].message.content')
CLEANED_CONTENT=$(echo "$RAW_CONTENT" | sed -e 's/^```json//' -e 's/^```//' -e 's/```$//')

FILES_JSON=$(echo "$CLEANED_CONTENT" | jq -e '.' 2>/dev/null)
if [[ -z "$FILES_JSON" ]]; then
  echo "❌ No valid JSON object found in model response."
  exit 1
fi

for key in $(echo "$FILES_JSON" | jq -r 'keys[]'); do
  FILENAME="$key"
  CODE_SNIPPET=$(echo "$FILES_JSON" | jq -r --arg key "$key" '.[$key]')
  CODE_SNIPPET=$(echo "$CODE_SNIPPET" | sed 's/\r$//')
  save_to_file "$FILENAME" "$CODE_SNIPPET"
done

echo "✅ All files generated successfully."
echo "📁 Generated file tree:"
find autocoder-bot
