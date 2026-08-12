# ☂️ Ausilio Umbrel App Store

The official **Ausilio Community App Store** for [umbrelOS](https://umbrel.com).

Fully compatible with **Raspberry Pi (ARM64)** and **x86_64** Umbrel installations.

## 📦 Included Applications

All apps are configured with non-conflicting default ports and dynamic port assignment via `${APP_PORT}`.

| App ID | App Name | Category | Default Port | ARM64 (Raspberry Pi) | Description |
| --- | --- | --- | --- | --- | --- |
| `ausilio-appflowy` | **AppFlowy** | Productivity | 18001 | ✅ Supported | Open-source alternative to Notion |
| `ausilio-erpnext` | **ERPNext** | Business | 18002 | ✅ Supported | Complete open-source ERP system |
| `ausilio-documenso` | **Documenso** | Business | 18003 | ✅ Supported | Open-source document signing platform |
| `ausilio-fluidvoice` | **FluidVoice** | Utilities | 18004 | ✅ Supported | Speech-to-text dictation & transcription service |
| `ausilio-cal-diy` | **Cal.diy** | Productivity | 18005 | ✅ Supported | Community scheduling infrastructure (Cal.com) |
| `ausilio-dub` | **Dub** | Marketing | 18006 | ✅ Supported | Open-source link management and URL shortener |
| `ausilio-listmonk` | **Listmonk** | Communication | 18007 | ✅ Supported | High-performance newsletter & mailing list manager |

## 🚀 How to Install on umbrelOS

1. Log into your **umbrelOS** dashboard (Raspberry Pi or PC).
2. Open the **App Store**.
3. Click the three dots (**⋮**) in the top right corner and select **Community App Stores**.
4. Click **Add App Store**.
5. Enter your repository URL:
   ```
   https://github.com/<your-username>/umbrel-app-store
   ```
6. Click **Add**. **Ausilio Umbrel App Store** will appear in your store list, ready for 1-click installation!
