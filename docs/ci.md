# CI / Fork Setup

## Telegram Notifications (Optional)

1. Create a bot via [@BotFather](https://t.me/BotFather), copy the token
2. Get your chat ID: `https://api.telegram.org/botYOUR_TOKEN/getUpdates`
3. Add to repo → **Settings → Secrets → Actions**:

| Secret | Value |
|--------|-------|
| `TELEGRAM_BOT_TOKEN` | your bot token |
| `TELEGRAM_CHAT_ID` | your chat ID |
| `TELEGRAM_TOPIC_ID` | (Optional) topic message thread ID |

---

## Running a Build

Actions tab → pick a workflow → **Run workflow**

| Workflow | Target |
|----------|--------|
| `Build Kernels — AIO` | Android 15+ (GKI + CLO, all variants) |
| `Build GKI-Compat` | Android 13 / 14 (GKI-Compat variants) |

**ZIP packaging mode** (AIO only):
- `per-variant` — individual ZIP per variant
- `aio` — single ZIP with all images
- `both` — individual ZIPs + AIO ZIP
