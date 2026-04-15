# AppLocker - Complete Setup & Configuration Guide

## 📋 Table of Contents
1. [Prerequisites](#prerequisites)
2. [Parent Dashboard Setup](#parent-dashboard-setup)
3. [Child Device Setup](#child-device-setup)
4. [Pairing Process](#pairing-process)
5. [Configuration & Controls](#configuration--controls)
6. [Testing & Verification](#testing--verification)
7. [Troubleshooting](#troubleshooting)

---

## Prerequisites

### What You Need
- **Parent Device:** PC/Mac/Tablet with a web browser (Chrome, Firefox, Safari)
- **Child Device:** Android device (API 24+, Android 7.0+)
- **Internet Connection:** WiFi or mobile data (for both devices and Firestore sync)
- **Google/Firebase Account:** For authentication

### Important Permissions to Grant
These permissions must be granted on the **child device** for AppLocker to work:

1. **Device Administrator**
   - Allows app to lock/unlock the device
   - Required for overlay and lock screen features

2. **Display over other apps (Draw over other apps)**
   - Allows system overlay for lock screen and app blocking
   - Critical for blocking apps across the entire device

3. **Usage Access**
   - Allows app to detect which app is currently open
   - Required for per-app blocking (Basic Mode)

4. **Location Permission** (Optional but recommended)
   - Allows real-time GPS location tracking
   - Parent can see device location on dashboard

5. **Camera Permission**
   - Used for QR code scanning during pairing

---

## Parent Dashboard Setup

### Step 1: Access the Parent Dashboard

**Option A: Local Testing**
```bash
cd AppLocker
flutter run --target lib/dashboard/main_web.dart -d chrome
```

**Option B: Production URL**
- Navigate to: `https://your-firebase-hosting-url.web.app`

### Step 2: Create Parent Account

1. Click **"Parent Login"** on the splash screen
2. Click **"Sign Up"** to create a new account
3. Enter:
   - **Email:** Your parent email address
   - **Password:** Strong password (min 6 characters)
4. Click **"Create Account"**
5. You'll be redirected to the dashboard after signup

### Step 3: Understand the Dashboard Menu

- **Main:** Overview of paired devices, statistics
- **Devices:** List of paired child devices with status
- **Users:** View assigned parent/child relationships
- **Apps:** Browse installed apps on child device, configure blocking rules
- **Reports:** View usage statistics and activity logs
- **Schedules:** Set time-based lock schedules
- **Settings:** Change email, password, app preferences

---

## Child Device Setup

### Step 1: Install the Child APK

1. Build and install the release APK:
```bash
flutter build apk --release --target lib/child/main_child.dart
flutter install -v
```

2. Or manually transfer and install `app-release.apk` to the child device

3. Open the app on the child device

### Step 2: Grant Required Permissions

The app will request permissions on first launch:

#### ✅ **Device Administrator** (CRITICAL)
1. When prompted, click **"Request Admin Permission"**
2. Select **"AppLocker"** from the list
3. Click **"Activate this device admin app"**
4. Confirm in the popup

#### ✅ **Display Over Other Apps**
1. Click **"Request Overlay Permission"** if prompted
2. Go to: **Settings → Apps → Special app access → Display over other apps**
3. Find **"AppLocker"** and toggle **ON**

#### ✅ **Usage Access**
1. Click **"Request Usage Permission"** if prompted
2. Go to: **Settings → Apps & notifications → Advanced → Special app access → Usage access**
3. Find **"AppLocker"** and toggle **ON**

#### ✅ **Location Permission**
1. Go to: **Settings → Apps → Permissions → Location**
2. Find **"AppLocker"** and set to **"Allow all the time"** (or "Allow while using the app")

#### ✅ **Camera Permission** (for QR pairing)
1. Go to: **Settings → Apps → Permissions → Camera**
2. Find **"AppLocker"** and toggle **ON**

### Step 3: Start the App

1. Open **AppLocker** on the child device
2. You should see the home screen with:
   - Device ID (8-character code)
   - "Scan QR Code to Pair" button
   - Device status (Online/Offline)

---

## Pairing Process

### Method 1: QR Code Pairing (Recommended)

#### On Parent Dashboard:
1. Click **"Add Device"** button (blue pill button on main screen)
2. A **QR code** will be displayed in the dialog
3. Keep this QR code visible on your parent device screen

#### On Child Device:
1. Click **"Scan QR Code to Pair"** button
2. Point the camera at the QR code on the parent device
3. When the QR is recognized, the app automatically pairs
4. You'll see **"Pairing successful!"** notification

### Method 2: Manual PIN Entry (If QR Fails)

#### On Parent Dashboard:
1. Click **"Add Device"** button
2. A **6-digit PIN code** will be displayed above the QR code
3. Note this PIN code

#### On Child Device:
1. Click **"Pair with PIN Code"** (if available)
2. Enter the 6-digit PIN code manually
3. Click **"Pair"**
4. Confirmation message appears

### After Pairing:
- Device will appear in the **"Devices"** tab on the dashboard
- Status changes to **"Online"** once child device syncs with Firestore
- Installed apps from the child device start syncing automatically

---

## Configuration & Controls

### A. Device Lock/Unlock (Full-Screen Lock)

#### From Parent Dashboard:
1. Go to **"Devices"** tab
2. Find your child device
3. Click the **"Lock"** button (lock icon)
4. Device will immediately show the lock screen on the child device

#### On Child Device:
1. PIN entry screen appears (default PIN: **1234**)
2. Enter PIN to unlock
3. Or wait 5 minutes for auto-unlock (safety timeout)

#### To Unlock from Dashboard:
1. Click the **"Unlock"** button next to the locked device
2. Or send the app a command: **"show_overlay" → "hide_overlay"**

### B. Per-App Blocking (Apps Tab)

#### Setup:
1. Go to **"Apps"** tab on the parent dashboard
2. Select a device from the dropdown
3. Wait for **"Installed Apps"** to load (first sync takes 30 seconds)

#### Block an App:
1. Find the app in the list
2. Click the app row to expand controls
3. Select control mode:
   - **Allow** - App can be used freely
   - **Overlay** - Basic mode: Show warning overlay when app is opened
   - **Hidden** - Advanced mode: App is hidden from launcher (requires Device Admin)

#### Save Changes:
1. Changes auto-sync to the child device
2. On the child device, you'll see the overlay when trying to open a blocked app

### C. Manage Control Mode (Basic vs Advanced)

#### Basic Mode (Overlay Warning):
- Shows a warning screen when a blocked app is opened
- User can dismiss and try again
- Less restrictive

#### Advanced Mode (App Hiding):
- Blocked apps are removed from the launcher
- Apps cannot be launched
- More secure

#### Switch Mode:
1. Go to **"Apps"** tab
2. Find **"Control Mode"** setting
3. Select **"Basic"** or **"Advanced"**
4. Click **"Apply"**

### D. Time-Based Locking (Schedules Tab)

#### Create a Schedule:
1. Go to **"Schedules"** tab
2. Click **"Add New Schedule"**
3. Set:
   - **Start Time:** e.g., 22:00 (10 PM)
   - **End Time:** e.g., 06:00 (6 AM)
4. Click **"Save Schedule"**

#### During Scheduled Time:
- Device automatically locks at start time
- Device automatically unlocks at end time
- Child sees lock screen and needs PIN to unlock (if manual unlock needed)

---

## Testing & Verification

### Verify Parent Dashboard Connection:
1. Open dashboard at `http://localhost:5173` or your web URL
2. Login with parent email
3. Go to **"Devices"** tab
4. You should see your paired device with status **"Online"**

### Verify Child Device Setup:
1. Open AppLocker on child device
2. Check:
   - ✅ Device ID is displayed
   - ✅ Status shows **"Online"** (after ~30 seconds)
   - ✅ Battery percentage is updated
   - ✅ Location is showing (if location permission granted)

### Test Lock/Unlock:
1. **From Dashboard:**
   - Click **"Lock"** on the device
   - Child device should show lock screen immediately
   - Click **"Unlock"** on dashboard
   - Child device lock screen should disappear

2. **Test PIN:**
   - Lock the device
   - On child device, enter PIN: **1234**
   - Device should unlock

### Test App Blocking:
1. **Set an app to "Overlay" mode:**
   - Go to **"Apps"** tab
   - Find an app (e.g., YouTube)
   - Select **"Overlay"** mode
   - Wait 5 seconds for sync

2. **On child device:**
   - Try to open the blocked app
   - An overlay should appear saying **"App Restricted"**
   - Click **"Return Home"** to go back

### Test Schedule:
1. **Create a test schedule:**
   - Set start time to current time
   - Set end time to 1 minute from now
2. **Verify:**
   - Device should lock immediately
   - After 1 minute, device should automatically unlock

---

## Troubleshooting

### Issue: "Device not syncing" / Status shows "Offline"

**Causes:**
- No internet connection
- Background service not running
- Firebase connection issue

**Solutions:**
1. Check WiFi/mobile data connection on child device
2. Restart the AppLocker app
3. Make sure app has **"Battery Optimization"** disabled (Settings → Battery → App Battery Usage)
4. Check Firebase console for errors

### Issue: Lock Screen Not Appearing

**Causes:**
- Device Administrator permission not granted
- Overlay permission missing
- App was force-stopped

**Solutions:**
1. Go to **Settings → Apps → Special app access → Device admin apps**
   - Ensure **"AppLocker"** is enabled
2. Go to **Settings → Apps → Special app access → Display over other apps**
   - Ensure **"AppLocker"** is enabled
3. Restart the app
4. Rebuild and reinstall if still not working

### Issue: App Overlay (Blocking) Not Working

**Causes:**
- Usage access permission not granted
- App not in the blocked list
- Control mode set to "Allow" instead of "Overlay"

**Solutions:**
1. Check **Settings → Apps → Advanced → Special app access → Usage access**
   - Ensure **"AppLocker"** is enabled
2. Verify app is listed in the **"Apps"** tab
3. Ensure app control is set to **"Overlay"** not **"Allow"**
4. Wait 10 seconds after changing mode (sync delay)

### Issue: "Cannot Pair" / QR Code Not Scanning

**Causes:**
- Poor lighting
- QR code too small
- Camera permission not granted

**Solutions:**
1. Ensure **"Camera"** permission is granted
2. Hold device steady under bright light
3. Move closer to/further from the QR code
4. Use manual PIN entry as fallback

### Issue: Dashboard Shows "No Authenticated User"

**Causes:**
- Parent account not logged in
- Session expired
- Firebase authentication issue

**Solutions:**
1. Click **"Logout"** and login again
2. Clear browser cache and cookies
3. Check Firebase console for authentication errors
4. Try a different browser

### Issue: App Keeps Crashing

**Causes:**
- Outdated app version
- Corrupted cache
- Permission conflicts

**Solutions:**
1. Uninstall and reinstall the APK
2. Clear app data: **Settings → Apps → AppLocker → Storage → Clear Data**
3. Check logs: `adb logcat | grep AppLocker`
4. Ensure all required permissions are granted

---

## Common PIN/Password Defaults

| Item | Default Value |
|------|---------------|
| Child Device PIN | `1234` |
| Parent Password | (User-defined during signup) |
| Default Control Mode | `basic` |
| Auto-unlock Timeout | 5 minutes |

## Changing the PIN

1. **On Parent Dashboard:**
   - Go to **"Apps"** tab
   - Scroll to **"Device Settings"**
   - Change PIN and click **"Update"**

2. **Sync to Child:**
   - Changes sync immediately to child device
   - Child device will request the new PIN on next lock

---

## Security Best Practices

1. **Use Strong Parent Password:**
   - Min 8 characters with uppercase, lowercase, numbers, symbols
   - Never share with child

2. **Change Default PIN Regularly:**
   - Change from `1234` to a custom 4-6 digit PIN
   - Don't use obvious patterns (1111, 1234, 0000)

3. **Keep Device Admin Active:**
   - Never disable Device Admin for AppLocker
   - This breaks all lock/overlay features

4. **Monitor Activity:**
   - Check **"Reports"** tab weekly
   - Review app usage and blocked attempts

5. **Backup Important Data:**
   - Sync child device data to Google Drive/Cloud
   - Create recovery codes for parent account

---

## Support & Additional Help

### Check Logs:
```bash
adb logcat -s AppLocker | grep "TEST:"
```

### View Firebase Console:
1. Go to: `https://console.firebase.google.com`
2. Select your project
3. Go to **"Firestore Database"** → **"Collections"** → **"devices"**
4. Find your device document and verify data sync

### Contact Support:
- Documentation: See `TECHNICAL_DOCUMENTATION.md`
- GitHub Issues: (if applicable)

---

## Congratulations! 🎉

Your AppLocker app is now fully configured and ready to use. For the best experience:

1. ✅ Grant all required permissions on child device
2. ✅ Pair child device with parent dashboard
3. ✅ Add apps to block/monitor in the **"Apps"** tab
4. ✅ Set device lock schedules if needed
5. ✅ Monitor device activity from the parent dashboard

**Happy Parental Control! 👨‍👩‍👧**
