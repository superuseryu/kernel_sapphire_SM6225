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
| `Build Kernels — AIO` | Android 15+ (GKI, all variants) |
| `Build GKI-Compat` | Android 13 / 14 (GKI-Compat variants) |

**ZIP packaging mode** (AIO only):
- `per-variant` — individual ZIP per variant
- `aio` — single ZIP with all images
- `both` — individual ZIPs + AIO ZIP

---

## Signing Secrets (Required)

### ZIP Signing Key (ED25519)

Generate a keypair:

```bash
openssl genpkey -algorithm ED25519 -out seiran-sign.key
openssl pkey -in seiran-sign.key -pubout -outform DER | tail -c 32 > pub.raw
```

Keep `seiran-sign.key` private. `pub.raw` goes into the ZIP for verification.

Add to repo → **Settings → Secrets → Actions**:

| Secret | Value |
|--------|-------|
| `SEIRAN_SIGN_KEY` | contents of `seiran-sign.key` |

```bash
gh secret set SEIRAN_SIGN_KEY -R <your-fork> < seiran-sign.key
```

### App Signing Keystore

Generate a keystore:

```bash
keytool -genkeypair -keystore seiran-app.jks -alias seiran \
  -groupname secp256r1 -validity 10000 \
  -dname "CN=Seiran"
```

Note the password — you'll need it for `SEIRAN_APP_KS_PASS`.

Add to repo → **Settings → Secrets → Actions**:

| Secret | Value |
|--------|-------|
| `SEIRAN_APP_KS_B64` | `seiran-app.jks` encoded as base64 |
| `SEIRAN_APP_KS_PASS` | keystore password |

```bash
gh secret set SEIRAN_APP_KS_B64 -R <your-fork> \
  -b "$(base64 -w0 seiran-app.jks)"

gh secret set SEIRAN_APP_KS_PASS -R <your-fork> \
  -b "your-password-here"
```
