# Demo GIF — Shot List

**Duration:** 30 seconds  
**Device:** Real iPhone (not simulator)  
**Prerequisites:** Local Mosquitto broker (127.0.0.1:1883), phone on same Wi-Fi

## Equipment

Two devices:
- **Mac:** running Mosquitto + terminal to publish MQTT messages
- **iPhone:** running CareElderly, screen recording

## Before Recording

1. Start Mosquitto: `brew services start mosquitto`
2. Confirm broker is reachable from iPhone (Settings → Server Configuration → host = Mac's LAN IP)
3. Open CareElderly on iPhone, log in as `guardian1` / `1234`
4. Start screen recording (Control Center → screen record)
5. Publish normal vital data for 10+ seconds so the chart has history:

```bash
# Publish 1 Hz for 10 seconds before switching to camera
while true; do
  mosquitto_pub -h localhost -t mmwave/vitals -m "{\"heart_rate_bpm\":72,\"respiratory_rate_rpm\":16,\"body_temperature_celsius\":36.7,\"timestamp_ms\":$(date +%s)000}"
  sleep 1
done
```

## Shot Sequence

| Sec | Frame | Action |
|-----|-------|--------|
| 0–2 | Home screen | Tap CareElderly icon to launch |
| 2–8 | Dashboard | Normal vital data streaming — HR ~72, BR ~16, Swift Charts scrolling, HRV cards populated |
| 8–18 | **Alert trigger (hero shot)** | Publish an anomaly message on Mac. Dashboard badge turns red (score ≥ 0.33). After 10 consecutive high-risk windows, full-screen popup appears + phone vibrates + Critical Alert push banner on lock screen |
| 18–23 | Alerts tab | Tap Acknowledge on popup → switch to Alerts tab → alert is recorded in list with timestamp/severity |
| 23–27 | Settings | Switch to Settings → Threshold Configuration → show adjustable sliders |
| 27–30 | Monitor | Switch back to Monitor tab → end recording |

## Anomaly Trigger Message

Publish this on the Mac when the Dashboard shot is looking good:

```bash
mosquitto_pub -h localhost -t mmwave/vitals -m '{"heart_rate_bpm":35,"respiratory_rate_rpm":8,"body_temperature_celsius":36.1,"timestamp_ms":'$(date +%s)'000}'
```

## Post-Processing

```bash
# Convert screen recording to GIF
ffmpeg -i screen-recording.mov \
  -vf "fps=12,scale=360:-1:flags=lanczos" \
  -loop 0 \
  demo.gif

# Target: 5–10 MB. Adjust fps/scale if needed.
```

## Placement

Replace the app icon placeholder in README.md:

```markdown
<!-- TODO: replace app icon with 30 s demo GIF -->
![App screenshot](CareElderly/Dark%20Icon.png)
```

becomes:

```markdown
![Demo](docs/demo.gif)
```
