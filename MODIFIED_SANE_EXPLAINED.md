# Modified-Sane: How Custom Commands Extended SANE

## Overview

The `modified-Sane` folder contains a customized version of the SANE (Scanner Access Now Easy) library that extends the standard PLUSTEK backend with **custom command options** that allow control over scanner behavior at runtime through the SANE frontend interface.

Instead of hardcoding scanner behavior, the modifications add **user-configurable options** that applications can set and query. This allows end-users (or applications) to dynamically control scanner features without recompiling code.

---

## Architecture: How Custom Commands Work in SANE

### 1. The SANE Option System

SANE applications communicate with backends through a **standardized option interface**:

```c
// Every backend defines a list of options (capabilities the scanner exposes)
sane_get_option_descriptor(handle, option_index)
    └─ Returns: Option name, type, constraints, current value

// Applications set options before scanning
sane_control_option(handle, option_index, action, value, info)
    └─ SANE_ACTION_SET_VALUE: Set the option value
    └─ SANE_ACTION_GET_VALUE: Get the option value

// When scanning starts, the backend reads these option values
sane_start(handle)
    └─ Uses the option values set earlier to configure hardware
```

### 2. Option Definition Process

Each custom command is defined as an **SANE_Option_Descriptor**:

```c
// Define what the user can control
struct SANE_Option_Descriptor {
    SANE_String_Const name;                  // "lamp-switch"
    SANE_String_Const title;                 // "Lampswitch"
    SANE_String_Const desc;                  // "Manually switching the lamp(s)."
    SANE_Value_Type type;                    // SANE_TYPE_BOOL
    SANE_Int size;                           // sizeof(SANE_Bool)
    SANE_Int cap;                            // Capabilities (read/write/settable)
    SANE_Constraint_Type constraint_type;    // SANE_CONSTRAINT_NONE
    SANE_Constraint constraint;              // Min/max/list of allowed values
};

// Store the current value
union {
    SANE_Bool b;
    SANE_Int w;
    SANE_Fixed f;
    SANE_String s;
    SANE_Word *wa;
} value;
```

---

## Custom Commands Added in Modified-Sane

### Version 0.47 - Basic Hardware Control

**OPT_LAMPSWITCH**
```c
s->opt[OPT_LAMPSWITCH].name  = "lamp-switch";
s->opt[OPT_LAMPSWITCH].title = "Lampswitch";
s->opt[OPT_LAMPSWITCH].desc  = "Manually switching the lamp(s).";
s->opt[OPT_LAMPSWITCH].type  = SANE_TYPE_BOOL;  // On/Off
s->val[OPT_LAMPSWITCH].w     = SANE_FALSE;

// User can now do:
scanimage --lamp-switch          // Turn lamp on before scan
scanimage --lamp-switch=0        // Turn lamp off
```

**OPT_WARMUPTIME**
```c
// Time (seconds) to warm up lamp before scanning
// Allows fine-tuning of lamp stability
```

### Version 0.48 - Configuration Cache & Override

**OPT_CACHECAL**
```c
s->opt[OPT_CACHECAL].name  = "calibration-cache";
s->opt[OPT_CACHECAL].title = "Calibration data cache";
s->opt[OPT_CACHECAL].desc  = "Enables or disables calibration data cache.";
s->opt[OPT_CACHECAL].type  = SANE_TYPE_BOOL;

// User can control whether calibration data is reused or recalculated:
scanimage --calibration-cache        // Use cached calibration (faster)
scanimage --calibration-cache=0      // Discard cache, recalibrate (better quality)
```

**OPT_OVR_*** (Model Override options)
```c
// Allow overriding device model detection
// Useful if scanner is misidentified:
scanimage --model-override=12       // Force specific model ID
```

**OPT_LAMPOFF_TIMER**
```c
// Time (seconds) before automatically shutting off lamp
// Extends lamp life:
scanimage --lampoff-timer=60        // Turn off after 60 seconds of inactivity
```

**OPT_LAMPOFF_ONEND**
```c
s->opt[OPT_LAMPOFF_ONEND].name  = "lamp-off-after-scan";
s->opt[OPT_LAMPOFF_ONEND].desc  = "Switches lamp off after scan is complete";
s->opt[OPT_LAMPOFF_ONEND].type  = SANE_TYPE_BOOL;

// Automatically switch off lamp when done scanning
scanimage --lamp-off-after-scan      // Enable feature
```

**OPT_BIT_DEPTH**
```c
// Select between 8-bit or 16-bit (14-bit) color depth
// Affects data size and quality:
scanimage --depth 8                  // Faster, smaller files (256 levels per channel)
scanimage --depth 16                 // Better quality, larger files (65536 levels)
```

### Version 0.50 - Performance Control

**OPT_SPEEDUP**
```c
// Enable/disable speed optimization
scanimage --speedup=yes              // Fast but may lose quality
scanimage --speedup=no               // Slower but higher quality
```

### Version 0.51 - Manual Calibration

**OPT_CALIBRATE**
```c
// Force manual calibration instead of using cached data
scanimage --calibrate                // Run calibration on every scan
```

### Version 0.52 - Dark Strip Control

**OPT_LOFF4DARK**
```c
s->opt[OPT_LOFF4DARK].name  = "lamp-off-during-dcal";
s->opt[OPT_LOFF4DARK].title = "Lamp off during dark calibration";
s->opt[OPT_LOFF4DARK].desc  = "Always switches lamp off when doing dark calibration.";
s->opt[OPT_LOFF4DARK].type  = SANE_TYPE_BOOL;
s->val[OPT_LOFF4DARK].w     = adj->skipDarkStrip;

// Dark calibration reads scanner in complete darkness
// This option controls lamp behavior during that phase:
scanimage --lamp-off-during-dcal     // Turn lamp off for accurate dark reference
```

---

## How Custom Commands Map to Hardware Control

### The Configuration File Chain

```
plustek.conf (system config file)
    ↓
    Scanner initialization → Load device defaults
    ↓
User sets options via sane_control_option()
    ↓
Option value stored in scanner->val[OPT_NAME]
    ↓
sane_start() called
    ↓
Backend reads option values -> Modifies registers -> Sends to hardware
```

### Example: Lamp Control Flow

```c
// 1. User application sets option
scanimage --lamp-switch

// 2. SANE receives control_option() call:
status = sane_control_option(handle, OPT_LAMPSWITCH, SANE_ACTION_SET_VALUE, 
                             value, info)

// 3. Backend stores value
scanner->val[OPT_LAMPSWITCH].w = (SANE_Bool)value;

// 4. When sane_start() is called, backend checks:
if (scanner->val[OPT_LAMPSWITCH].w == SANE_TRUE) {
    usb_LedOn(dev, SANE_TRUE);      // Send LED/lamp on command to USB device
}

// 5. Hardware receives command and turns on lamp
```

---

## Implementation: How Options Are Handled

### Step 1: Define Option Enum

**From plustek.c (lines 712-937):**

```c
// Option indices (ordinal position in option list)
enum {
    OPT_NUM_OPTS = 0,
    
    // Scan mode group
    OPT_MODE_GROUP,
    OPT_MODE,
    OPT_BIT_DEPTH,
    OPT_EXT_MODE,
    OPT_BRIGHTNESS,
    OPT_CONTRAST,
    OPT_RESOLUTION,
    
    // Enhancement group
    OPT_CUSTOM_GAMMA,
    OPT_PREVIEW,
    OPT_GAMMA_VECTOR,
    OPT_GAMMA_VECTOR_R,
    OPT_GAMMA_VECTOR_G,
    OPT_GAMMA_VECTOR_B,
    
    // Device settings group (CUSTOM COMMANDS)
    OPT_DEVICE_GROUP,
    OPT_LAMPSWITCH,          // V0.47
    OPT_LOFF4DARK,           // V0.52
    OPT_CACHECAL,            // V0.48
    OPT_WARMUPTIME,          // V0.47
    OPT_LAMPOFF_TIMER,       // V0.48
    OPT_LAMPOFF_ONEND,       // V0.48
    OPT_CALIBRATE,           // V0.51
    OPT_SPEEDUP,             // V0.50
    
    NUM_OPTIONS              // Total option count
};
```

### Step 2: Initialize Option Descriptors

**From plustek.c (lines 919-936):**

```c
/* Device settings group */
s->opt[OPT_DEVICE_GROUP].title = "Device-Settings";
s->opt[OPT_DEVICE_GROUP].desc  = "";
s->opt[OPT_DEVICE_GROUP].type  = SANE_TYPE_GROUP;
s->opt[OPT_DEVICE_GROUP].cap   = 0;

/* Lamp switch */
s->opt[OPT_LAMPSWITCH].name  = "lamp-switch";
s->opt[OPT_LAMPSWITCH].title = SANE_I18N("Lampswitch");
s->opt[OPT_LAMPSWITCH].desc  = SANE_I18N("Manually switching the lamp(s).");
s->opt[OPT_LAMPSWITCH].type  = SANE_TYPE_BOOL;
s->val[OPT_LAMPSWITCH].w     = SANE_FALSE;

/* Lamp off during dark calibration */
s->opt[OPT_LOFF4DARK].name  = "lamp-off-during-dcal";
s->opt[OPT_LOFF4DARK].title = SANE_I18N("Lamp off during dark calibration");
s->opt[OPT_LOFF4DARK].desc  = SANE_I18N("Always switches lamp off when...");
s->opt[OPT_LOFF4DARK].type  = SANE_TYPE_BOOL;
s->val[OPT_LOFF4DARK].w     = adj->skipDarkStrip;

/* Calibration cache */
s->opt[OPT_CACHECAL].name  = "calibration-cache";
s->opt[OPT_CACHECAL].title = SANE_I18N("Calibration data cache");
s->opt[OPT_CACHECAL].desc  = SANE_I18N("Enables or disables calibration cache");
s->opt[OPT_CACHECAL].type  = SANE_TYPE_BOOL;
```

### Step 3: Handle Option Control

The backend implements `sane_control_option()`:

```c
static SANE_Status
sane_control_option(SANE_Handle handle, SANE_Int option, SANE_Action action,
                    void *value, SANE_Int *info)
{
    Plustek_Scanner *scanner = (Plustek_Scanner *) handle;

    switch (action) {
    
    case SANE_ACTION_GET_VALUE:
        // Application reads current value
        *((SANE_Int*) value) = scanner->val[option].w;
        return SANE_STATUS_GOOD;

    case SANE_ACTION_SET_VALUE:
        // Application sets new value
        switch(option) {
        
        case OPT_LAMPSWITCH:
            // User wants to control lamp
            scanner->val[OPT_LAMPSWITCH].w = *((SANE_Bool*) value);
            if (*info) *info |= SANE_INFO_RELOAD_PARAMS;
            return SANE_STATUS_GOOD;
            
        case OPT_CACHECAL:
            // User wants to cache/discard calibration
            scanner->val[OPT_CACHECAL].w = *((SANE_Bool*) value);
            return SANE_STATUS_GOOD;
            
        case OPT_LOFF4DARK:
            // User wants lamp off during dark calibration
            scanner->val[OPT_LOFF4DARK].w = *((SANE_Bool*) value);
            return SANE_STATUS_GOOD;
            
        // ... other options ...
        }
        break;
    }
    
    return SANE_STATUS_UNSUPPORTED;
}
```

### Step 4: Use Option Values During Scan

**From plustek-usb.c (usbDev_Prepare function):**

```c
// When starting a scan, check what options user selected
if (scanner->val[OPT_LAMPSWITCH].w == SANE_TRUE) {
    usb_LedOn(dev, SANE_TRUE);  // Turn on lamp
}

if (scanner->val[OPT_CACHECAL].w == SANE_FALSE) {
    // Discard cached calibration, force recalibration
    dev->calibrating = SANE_TRUE;  
}

if (scanner->val[OPT_LAMPOFF_ONEND].w == SANE_TRUE) {
    // Remember to turn off lamp when scan completes
    dev->fAutoShutdown = SANE_TRUE;
}

// Similar for other options...
```

---

## Key Insight: Configuration → Options → Commands

The modified-Sane creates a **three-level control hierarchy**:

```
┌─────────────────────────────────────────────────────┐
│ Configuration Files (plustek.conf)                  │
│ - Loaded once at startup                            │
│ - Device-specific defaults                          │
│ - Stored in CnfDef structure                        │
└────────────┬────────────────────────────────────────┘
             │
             ↓ (Applied to device)
┌─────────────────────────────────────────────────────┐
│ SANE Options (OPT_LAMPSWITCH, OPT_CACHECAL, etc.)  │
│ - User-settable before each scan                    │
│ - Can override defaults from config file            │
│ - Stored in scanner->val[] array                    │
└────────────┬────────────────────────────────────────┘
             │
             ↓ (At sane_start())
┌─────────────────────────────────────────────────────┐
│ Hardware Commands (usbio_WriteReg, sanei_usb_*)    │
│ - Read option values                                │
│ - Translate to LM9832 register writes              │
│ - Send USB/IO commands to scanner                   │
│ - Immediate effect on hardware                      │
└─────────────────────────────────────────────────────┘
```

---

## Comparison: Standard SANE vs Modified-Sane

### Standard SANE (Original PLUSTEK Backend)

```
User → scanimage → sane_start()
        └─ No custom options
        └─ Hardcoded scanner behavior
        └─ Can't override decisions
        └─ Must recompile to change features
```

### Modified-Sane (Extended PLUSTEK Backend)

```
User → scanimage --lamp-switch --calibration-cache
        └─ SANE options available
        └─ Flexible scanner control
        └─ Can override per-scan
        └─ No recompilation needed
        
Configuration:
scanimage -d plustek -A          # List all options
scanimage -d plustek --help      # Show option descriptions
```

---

## Real-World Usage Examples

### Example 1: Quick Calibration

```bash
# Force recalibration (ignore cache) for highest quality
scanimage --lamp-switch --calibration-cache=0 \
          --lamp-off-during-dcal > scan.pnm
```

**What happens:**
1. OPT_LAMPSWITCH = TRUE → Manually turn on lamp
2. OPT_CACHECAL = FALSE → Discard cached data
3. OPT_LOFF4DARK = TRUE → Turn off lamp for dark reference
4. Scanner performs full calibration cycle
5. Higher quality scan at cost of longer setup time

### Example 2: Batch Scanning (Speed Optimized)

```bash
# Use cached calibration, enable speedup for fast batch processing
scanimage --speedup --calibration-cache \
          --lamp-off-after-scan > batch_1.pnm
scanimage --speedup --calibration-cache \
          --lamp-off-after-scan > batch_2.pnm
```

**What happens:**
1. OPT_CACHECAL = TRUE → Reuse calibration
2. OPT_SPEEDUP = TRUE → Use faster settings
3. OPT_LAMPOFF_ONEND = TRUE → Power down after each scan
4. Fast throughput, reasonable quality, lamp preserved

### Example 3: 16-bit High Quality Scan

```bash
# Full quality 16-bit scan with manual calibration
scanimage --depth 16 --calibrate \
          --brightness 50 --contrast 50 > hq_scan.pnm
```

**What happens:**
1. OPT_BIT_DEPTH = 16 → 16 bits per channel (65536 levels)
2. OPT_CALIBRATE = TRUE → Fresh calibration data
3. OPT_BRIGHTNESS/OPT_CONTRAST → Fine-tune sensor gain/offset
4. Maximum dynamic range and detail captured

---

## Summary: The Power of Extended Options

The modified-Sane approach demonstrates how **extending a SANE backend** with custom options enables:

1. **User Control**: Options appear in scanimage and GUI applications
2. **No Recompilation**: Features controlled at runtime
3. **Per-Scan Flexibility**: Different settings for different scans
4. **Hardware Optimization**: Fine-tune for quality, speed, or power consumption
5. **Device Support**: Work around manufacturer differences

Each custom command follows the pattern:
```
Define Option → Initialize Value → Handle Control → Use in Hardware Command
```

This modular approach keeps the hardware driver layer clean while providing powerful customization at the SANE interface level.
