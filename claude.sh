export ANTHROPIC_BASE_URL="http://localhost:4000"
export ANTHROPIC_AUTH_TOKEN=sk-1234
export ANTHROPIC_MODEL="claude-opus-4-7[1m]"
export ANTHROPIC_DEFAULT_OPUS_MODEL="claude-opus-4-7[1m]"
export ANTHROPIC_DEFAULT_SONNET_MODEL="claude-sonnet-4-6[1m]"
export ANTHROPIC_DEFAULT_HAIKU_MODEL="claude-haiku-4-5-20251001"
export CLAUDE_CODE_SUBAGENT_MODEL="claude-sonnet-4-6[1m]"
export CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1
export CLAUDE_CODE_DISABLE_NONSTREAMING_FALLBACK=1
export CLAUDE_CODE_EFFORT_LEVEL=max

claude --thinking-display summarized "$@"
