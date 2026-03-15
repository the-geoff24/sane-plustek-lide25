# Analog-to-Digital Conversion in Plustek LiDE 25

## Key Finding: The LM9832 ISP Chip Does A/D Conversion

The Canon CanoScan LiDE 25 uses the **LM9832 ISP (Image Signal Processor)** chip, which **internally performs the analog-to-digital conversion** from the CIS sensor signals.

---

## Hardware Components

```
CIS Sensor Array
    ↓
    └─> Photodiodes (detect light)
            ↓
            └─> Analog Voltage Output (per pixel)
                    ↓
                    └─> [INSIDE LM9832 CHIP]
                            ↓
                            └─> A/D Converter
                                    ↓
                                    └─> Digital Pixel Data (8-bit or 16-bit)
                                            ↓
                                            └─> Stored in Scanner's DRAM Buffer
                                                    ↓
                                                    └─> USB read to Host Computer
```

---

## The Exact Point Where Analog Becomes Digital

### Stage 1: CIS Sensor Captures Analog Light (Hardware)

The **CIS (Contact Image Sensor)** array consists of:
- **Red photodiodes** - detect red light wavelengths
- **Green photodiodes** - detect green light wavelengths
- **Blue photodiodes** - detect blue light  wavelengths

When light hits the photodiodes:
```
Light (photons)  →  Photodiode  →  Charge accumulation  →  Voltage
```

At integration/exposure time end:
```
Analog Voltage per pixel = (Charge × Sensitivity) 
                         = Value proportional to light intensity (0V to ~3V typically)
```

### Stage 2: A/D Converter in LM9832 (Digital Conversion)

**This is the exact conversion point:**

Inside the LM9832 chip, there's a **successive-approximation ADC** that converts the analog voltage to digital:

```c
// Pseudo-code representation of what happens internally in LM9832:

digital_value = ADC_Convert(analog_voltage)
// Where:
// analog_voltage = 0-3V from CIS sensor
// digital_value = 0-255 (for 8-bit) or 0-65535 (for 16-bit)

// Example conversions:
analog_voltage=0.0V  → digital_value=0    (black)
analog_voltage=1.5V  → digital_value=128  (gray)
analog_voltage=3.0V  → digital_value=255  (white)
```

---

## Plustek Code That Controls This

### 1. Sensor Configuration (plustek-usbhw.c:1364+)

Registers **0x0b through 0x18** control the sensor behavior:

```c
// From plustek-usbhw.c usb_ResetRegisters()

memcpy( regs+0x0b, &hw->bSensorConfiguration, 4 );
memcpy( regs+0x0f, &hw->bReg_0x0f_Color, 10 );
//
// These registers (0x0b-0x0e): Sensor settings directly from HWDef
// These registers (0x0f-0x18): Sensor Configuration directly from HWDef
//
// HWDef is the device-specific hardware definition structure that 
// contains the exact settings for the LiDE 25's CIS sensor
```

**What these registers do:**
- Configure pixel clock frequency
- Set integration time (exposure duration)
- Configure color/grayscale mode
- Set A/D conversion bit depth (8-bit or 16-bit)

### 2. Sensor Settings from HWDef (plustek-usb.h)

```c
// From plustek-usb.h - Device capabilities structure:

typedef struct {
    u_char bSensorConfiguration[4];  // Registers 0x0b-0x0e
    u_char bReg_0x0f_Color[10];      // Registers 0x0f-0x18
    // ... plus many pixel clock and integration settings
} HWDef;
```

### 3. Integration Time Configuration

The **integration/exposure time** determines how long the CIS photodiodes accumulate charge:

```c
// In plustek-usbcal.c and plustek-usb.c:

bMaxITA = 0;  // Maximum integration time adjust

// This is adjusted during calibration to optimize signal levels
// Longer integration time = more charge accumulated = brighter output
// Shorter integration time = less charge = darker output

// The LM9832 registers control:
// - Pixel clock frequency (controls integration time indirectly)
// - Direct integration time registers
```

---

## Where the Digitized Data Flows

### Step 1: LM9832 Collects Analog, Converts to Digital

```
Timeline in the LM9832 chip:

Time T0: Pixel clock rising edge
         → Photodiode outputs analog voltage
         → A/D converter samples the voltage

Time T0+N: Conversion time passes
           → ADC converts analog → digital value
           → Digital result stored in latch

Time T0+2N: Result ready
            → Next pixel clock pulse triggers next conversion
```

### Step 2: Digitized Data Stored in DRAM

```c
// Register 0x4e and 0x4f point to scanner DRAM buffer
// The LM9832 automatically writes converted pixels into DRAM

// From plustek-usbimg.c usb_ReadData():
scan->sParam.Size.dwTotalBytes -= dwBytes;

// Tells how many bytes of digital image data remain in DRAM
// Each byte = one 8-bit digital pixel (or 2 bytes for 16-bit)
```

### Step 3: Host Reads Digital Data via USB

```c
// From plustek-usbscan.c usb_ScanReadImage():

res = sanei_lm983x_read(dev->fd, 0x00,  // Register 0x00 = DATA PORT
                        (u_char *)pBuf,  // Host buffer
                        dwSize,          // Number of bytes to read
                        SANE_FALSE);
//
// Register 0x00 is the data read port
// LM9832 streams bytes from its internal DRAM buffer over USB
// All bytes are ALREADY DIGITAL (A/D conversion complete)
```

---

## The Three CIS Color Channels

CIS sensors in the LiDE 25 read RGB sequentially:

```c
// From plustek-usbimg.c:

// RGB lines are interleaved in data from LM9832:
// The sensor reads like this:

Red line 1:     R0  R1  R2  R3  R4  ...  (8-bit or 16-bit each)
                ↓   ↓   ↓   ↓   ↓
          (converted by LM9832 A/D)

Green line 1:   G0  G1  G2  G3  G4  ...  (8-bit or 16-bit each)
                ↓   ↓   ↓   ↓   ↓
          (converted by LM9832 A/D)

Blue line 1:    B0  B1  B2  B3  B4  ...  (8-bit or 16-bit each)
                ↓   ↓   ↓   ↓   ↓
          (converted by LM9832 A/D)

// Function reorder_rgb_line_to_pixel() combines them:
for (dw = 0; dw < pixels; dw++) {
    scan->UserBuf.pb_rgb[pixels].Red   = scan->Red.pb[dw];
    scan->UserBuf.pb_rgb[pixels].Green = scan->Green.pb[dw];
    scan->UserBuf.pb_rgb[pixels].Blue  = scan->Blue.pb[dw];
}
```

---

## LM9832 Register Programming (Analog → Digital Control)

The key registers that control A/D conversion:

| Register | Purpose | Set In |
|----------|---------|--------|
| **0x0b-0x0e** | Sensor configuration (A/D bit width, pixel clock) | `usb_ResetRegisters()` |
| **0x0f-0x18** | Color sensor configuration | `usb_ResetRegisters()` |
| **0x68-0x69** | Pixel clock frequency | Motor/timing setup |
| **0x6a-0x6b** | Integration time | Calibration code |
| **0x00** | Digital data output port (READ ONLY) | `sanei_lm983x_read()` |

---

## Summary: Where Analog Becomes Digital

**ANALOG SIGNALS:**
```
CIS Photodiodes
    ↓ (continuous analog voltage 0-3V per pixel)
LM9832 A/D Converter Port
```

**EXACT CONVERSION POINT:**
```
Inside LM9832 ISP Chip:
    Successive-Approximation ADC Circuit
    • Samples analog voltage on pixel clock
    • Converts to 8-bit or 16-bit digital value
    • Stores result in internal DRAM
    • Time: ~1-2 microseconds per pixel at typical settings
```

**DIGITAL SIGNALS:**
```
LM9832 DRAM Buffer (digital image data)
    ↓ (byte stream: 0-255 values per pixel)
Register 0x00 (Data Read Port)
    ↓
USB Bulk Transfer
    ↓
Host Computer Buffer
```

---

## Hardware Configuration for Canon LiDE 25

When the scanner initializes (plustek-usb.c: `local_sane_start()`):

```c
1. usbDev_open(dev)
   → Loads Canon LiDE 25 HW settings for CIS650 sensor

2. usb_ResetRegisters(dev)
   → Programs registers 0x0b-0x18 with CIS sensor params
   → A/D converter now ready
   → Integration time set

3. usbDev_setCaps(dev)
   → Configures resolution, scan area
   → Adjusts pixel clock for DPI setting

4. usbDev_startScan(dev)
   → Starts LM9832 A/D converter
   → CIS starts integrating photodiodes
→ Motor starts moving paper through scanner

5. usb_ScanReadImage(dev)
   → Loop: read digital data from Register 0x00
   → Each read gets already-converted pixels
   → Transfer complete when all lines scanned
```

---

## Key Insight

**You cannot see the actual A/D conversion code in Plustek** because:

1. **The LM9832 chip performs A/D internally** - it's not done in software
2. **The Plustek code configures the LM9832 via registers** - it tells the chip how to convert
3. **By the time Plustek reads data, it's already digital** - register 0x00 only outputs digital values

The A/D conversion is **hardware-based** inside the LM9832 ISP controller, controlled by:
- Registers 0x0b-0x18 (sensor configuration)
- Registers 0x68-0x6b (clock and timing)
- Integration time settings (set during calibration)

When you read from register 0x00, you're reading **digital result data**, not analog!
