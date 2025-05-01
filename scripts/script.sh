#!/bin/bash
set -e
set -x

# 获取输入参数
GITHUB_TOKEN="$1"
REPOSITORY="$2"
ISSUE_NUMBER="$3"
DEEPSEEK_API_KEY="$4"

# 获取issue内容函数
fetch_issue_details() {
    curl -s -H "Authorization: token $GITHUB_TOKEN" \
         "https://api.github.com/repos/$REPOSITORY/issues/$ISSUE_NUMBER"
}

# 调用DeepSeek API函数
send_prompt_to_deepseek() {
    curl --retry 3 --retry-delay 2 -s -X POST "https://api.deepseek.com/v1/chat/completions" \
    -H "Authorization: Bearer $DEEPSEEK_API_KEY" \
    -H "Content-Type: application/json" \
    -d "{
      \"model\": \"deepseek-coder-33b-instruct\",
      \"messages\": $MESSAGES_JSON,
      \"temperature\": 0.3,
      \"max_tokens\": 2000,
      \"top_p\": 0.95
    }"
}

# 保存文件函数
save_to_file() {
    local filename="autocoder-bot/$1"
    local code_snippet="$2"
    mkdir -p "$(dirname "$filename")"
    echo -e "$code_snippet" > "$filename"
    echo "Generated: $filename"
}

# 主流程
RESPONSE=$(fetch_issue_details)
ISSUE_BODY=$(echo "$RESPONSE" | jq -r .body)

[ -z "$ISSUE_BODY" ] && { echo "Empty issue body"; exit 1; }

INSTRUCTIONS="Generate a JSON object with file paths as keys and production-ready code as values. Response must be pure JSON without markdown."
FULL_PROMPT="$INSTRUCTIONS\n\n$ISSUE_BODY"

MESSAGES_JSON=$(jq -n --arg body "$FULL_PROMPT" '[{"role": "user", "content": $body}]')

# 调用API并处理错误
RESPONSE=$(send_prompt_to_deepseek)
if [ -z "$RESPONSE" ]; then
    echo "API request failed"
    exit 1
fi

# 错误处理增强
API_ERROR=$(echo "$RESPONSE" | jq -r '.error.message // empty')
if [ -n "$API_ERROR" ]; then
    echo "DeepSeek API Error: $API_ERROR"
    exit 1
fi

# 提取并验证JSON
FILES_JSON=$(echo "$RESPONSE" | jq -e '.choices[0].message.content | fromjson')
if [ $? -ne 0 ]; then
    echo "Invalid JSON response"
    echo "Raw response: $RESPONSE"
    exit 1
fi

# 生成文件
echo "$FILES_JSON" | jq -r 'to_entries[] | "\(.key)\n\(.value)"' | while read -r key && read -r value; do
    save_to_file "$key" "$value"
done

echo "All files generated successfully"
