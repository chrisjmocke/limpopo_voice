# Let's Talk - Universal Android Installation Guide

## 📱 Which APK Should You Use?

### Option 1: **UNIVERSAL APK** (RECOMMENDED - Works on ALL phones)
**File:** `LimpopoVoice-UNIVERSAL-59MB.apk`
- **Size:** 59 MB
- **Compatibility:** Works on **literally every Android phone** (API 21+)
- **Use this if:** You're not sure which version your phone needs, or your phone is very old (pre-2017)
- **Install:** Simply transfer this file to your phone and tap to install

---

### Option 2: **64-bit APK** (For most modern phones since ~2017)
**File:** `LimpopoVoice-64bit-NewerPhones-27MB.apk`
- **Size:** 27 MB
- **Best for:** Modern phones (Android 6.0+, most devices from 2017 onwards)
- **Faster/Smaller:** Optimized for 64-bit processors
- **Install:** Transfer to phone, tap to install

---

### Option 3: **32-bit APK** (For older phones)
**File:** `LimpopoVoice-32bit-OlderPhones-25MB.apk`
- **Size:** 25 MB
- **Best for:** Very old phones (2015-2017), phones with 32-bit CPU only
- **Smallest file:** If you have limited data/storage
- **Install:** Transfer to phone, tap to install

---

## 🚀 How to Install on Your Phone

### Method A: Direct Download & Install (Easiest)
1. **On your phone:** Open this file on your phone (via email, USB, cloud storage, or download link)
2. **If prompted:** Allow installation from unknown sources (Settings → Security → Unknown Sources)
3. **Tap:** "Install"
4. **Done:** App appears on home screen after installation

### Method B: USB Transfer
1. **Connect phone** to computer via USB cable
2. **Copy APK file** to phone storage (any folder)
3. **On phone:** Open file manager → find the APK file → tap it
4. **Allow:** Installation from unknown sources if prompted
5. **Tap:** "Install"

### Method C: ADB (Advanced Users)
```powershell
# Connect phone via USB, enable USB debugging
adb install -r "LimpopoVoice-UNIVERSAL-59MB.apk"
```

---

## ✅ Minimum Requirements

| Requirement | Details |
|---|---|
| **Android Version** | 5.0+ (API 21+) |
| **Storage** | 100 MB free space |
| **Internet** | Required for translation & audio playback |
| **Google Play Services** | Not required (but recommended) |

---

## 🔧 Troubleshooting

### "Installation blocked" or "Cannot install"
- **Solution:** Go to Settings → Security → Enable "Unknown Sources"
- **Then:** Retry installation

### "App not compatible with this device"
- **Try:** The UNIVERSAL APK instead (59 MB version)
- **If still fails:** Your phone may be running Android 4.x (too old)

### "App crashes on startup"
- **Uninstall** the app completely
- **Try** the UNIVERSAL APK
- **If still crashes:** Check Firebase availability (requires Google Play Services or Firebase components)

### "No audio / Translation fails"
- **Check:** Your internet connection
- **Check:** App has microphone permission (Settings → Apps → Let's Talk → Permissions)
- **Restart:** App and try again

### "App too slow / Cold start slow"
- **First translation:** May take 5-10 seconds (server warming up)
- **Subsequent:** Should be fast (cached)
- **This is normal** on slower connections

---

## 📦 File Summary

| File | Size | CPU Support | Best For |
|---|---|---|---|
| UNIVERSAL | 59 MB | All (ARMv7, ARMv8, x86, x86_64) | Any phone, guaranteed works |
| 64-bit | 27 MB | ARM64 only | Modern phones (2017+) |
| 32-bit | 25 MB | ARM32 only | Old phones (2015-2017) |

---

## ❓ How to Know Your Phone's CPU?

**Quick Check:**
1. Go to **Settings** → **About Phone** → **Processor** or **CPU info**
2. Look for: ARMv7, ARMv8, ARM64, x86, or "Snapdragon", "Exynos", "Kirin", etc.

**If Unsure:** Just use the **UNIVERSAL APK** — it will always work.

---

## 🎯 Recommended Installation Path

```
1. Download UNIVERSAL APK → LimpopoVoice-UNIVERSAL-59MB.apk
2. Transfer to phone
3. Install
4. Open app → Accept disclaimer
5. Done!
```

**Why?** It guarantees compatibility on the widest range of devices, including phones from 2014+.

---

## 📞 Support

If installation still fails after trying all steps:
1. Check your Android version (Settings → About Phone)
2. Ensure you have 100+ MB free storage
3. Restart phone and retry
4. Try the UNIVERSAL APK if you haven't already

---

**Last Updated:** May 12, 2026  
**App:** Let's Talk v1.0  
**Status:** Universal Android support (API 21+)
