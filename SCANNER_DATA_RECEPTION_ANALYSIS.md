# How Plustek Scanner Receives Data - Complete Analysis

## Overview

The Plustek backend uses a **multi-layered architecture** to receive image data from the scanner. Data flows from the USB device through several layers of abstraction, ultimately being buffered and delivered to the application.

```
┌─────────────────────────────────────────────────────────────────┐
│                    Application Layer                             │
│                    (scanimage CLI tool)                          │
└─────────────────────┬───────────────────────────────────────────┘
                      │ sane_read()
┌─────────────────────▼───────────────────────────────────────────┐
│                   SANE Backend (plustek.c)                       │
│  ┌──────────────────────────────────────────────────────────┐   │
│  │ Manages: Options, Parameters, Scan Initiation           │   │
│  │ Calls: local_sane_start(), reader_process()             │   │
│  └──────────────────────────────────────────────────────────┘   │
└─────────────────────┬───────────────────────────────────────────┘
                      │ pipe() - IPC with child process
┌─────────────────────▼───────────────────────────────────────────┐
│              Data Reception Pipeline                             │
│  ┌──────────────────────────────────────────────────────────┐   │
│  │ 1. usb_ReadData() - Line-by-line reading                │   │
│  │ 2. usb_ScanReadImage() - Buffer management              │   │
│  │ 3. sanei_lm983x_read() - Vendor-specific USB commands   │   │
│  └──────────────────────────────────────────────────────────┘   │
└─────────────────────┬───────────────────────────────────────────┘
                      │
┌─────────────────────▼───────────────────────────────────────────┐
│         SANEI USB Abstraction (sanei_usb.c)                     │
│  ┌──────────────────────────────────────────────────────────┐   │
│  │ - Device Management                                      │   │
│  │ - Bulk Transfer Operations                              │   │
│  │ - libusb Integration                                    │   │
│  └──────────────────────────────────────────────────────────┘   │
└─────────────────────┬───────────────────────────────────────────┘
                      │ libusb_bulk_transfer()
┌─────────────────────▼───────────────────────────────────────────┐
│                     USB Layer                                    │
│              libusb-1.0 Library                                  │
└─────────────────────┬───────────────────────────────────────────┘
                      │ USB Protocol
┌─────────────────────▼───────────────────────────────────────────┐
│                Canon CanoScan LiDE 25                           │
│         (LM9832 ISP Controller + CIS Sensor)                   │
└─────────────────────────────────────────────────────────────────┘
```

---

## 1. Scan Initiation Flow

### Step 1.1: `sane_start()` - Initialize Scanning (plustek.c:2575)

```c
SANE_Status sane_start(SANE_Handle handle)
{
    Plustek_Scanner *s = (Plustek_Scanner *)handle;
    
    // 1. Check if device is busy
    if (s->scanning) return SANE_STATUS_DEVICE_BUSY;
    
    // 2. Configure scan parameters
    status = local_sane_start(s, getScanMode(s));
    
    // 3. Create IPC pipe: fds[0]=read, fds[1]=write
    pipe(fds);
    
    // 4. Fork reader process to read from scanner in background
    s->reader_pid = sanei_thread_begin(reader_process, s);
    
    s->scanning = SANE_TRUE;
}
```

**Key Points:**
- Opens USB device connection
- Validates scanner capabilities
- Calculates crop area (scan region)
- Downloads gamma correction tables
- Starts USB scan with `usbDev_startScan()`
- Creates child process to read data from scanner

### Step 1.2: `local_sane_start()` - Configuration (plustek.c:2385)

```c
static SANE_Status local_sane_start(Plustek_Scanner *s, int scanmode)
{
    // 1. Open USB device
    dev->fd = usbDev_open(dev, NULL, SANE_TRUE);
    
    // 2. Get scanner capabilities
    usbDev_getCaps(dev);
    
    // 3. Calculate crop area (scan region) from SANE options
    //    - Resolution (DPI)
    //    - Top-left corner (TL_X, TL_Y)
    //    - Bottom-right corner (BR_X, BR_Y)
    crop.ImgDef.xyDpi.x = ndpi;
    crop.ImgDef.xyDpi.y = ndpi;
    crop.ImgDef.crArea.cx = width;   // pixels per line
    crop.ImgDef.crArea.cy = height;  // lines to scan
    
    // 4. Get crop information from scanner
    usbDev_getCropInfo(dev, &crop);
    
    // 5. Set scan environment (brightness, contrast)
    usbDev_setScanEnv(dev, &sinfo);
    
    // 6. Download gamma correction tables
    usbDev_setMap(dev, gamma_table, length, _MAP_MASTER);
    
    // 7. Start the scan on hardware
    usbDev_startScan(dev);
    
    // 8. Allocate buffer for image data
    s->buf = malloc(s->params.lines * s->params.bytes_per_line);
}
```

---

## 2. Reader Process - Background Data Reception

### The Reader Process

A child process is created to read data continuously from the scanner:

```c
/* pseudo code - simplified representation */
void* reader_process(Plustek_Scanner *s)
{
    Plustek_Device *dev = s->hw;
    
    // Main loop: keep reading until scan complete
    while (/*scan not done*/) {
        
        // Read image lines from scanner
        linesToRead = usb_ReadData(dev);
        
        if (linesToRead == 0) break;
        
        // Write data to pipe for main process
        write(s->w_pipe, data_buffer, bytes_read);
    }
    
    return result;
}
```

**Why a child process?**
- USB reads block (take time while waiting for scanner)
- Main process stays responsive to application
- Application can cancel at any time
- Efficient streaming of data

---

## 3. Core Data Reception Functions

### Function 3.1: `usb_ReadData()` - Line-by-Line Reading (plustek-usbimg.c:1895)

This is the **main data pump** that reads raw image data from scanner:

```c
static SANE_Int usb_ReadData(Plustek_Device *dev)
{
    u_long dwBytes, dwTotalBytes;
    ScanDef *scan = &dev->scanning;
    
    // dwTotalBytes = total image size in bytes
    while (scan->sParam.Size.dwTotalBytes > 0) {
        
        // 1. Get chunk size to read (limited by buffer)
        if (totalbytes > scanBufferSize)
            dwBytes = scanBufferSize;  // Read max buffer size
        else
            dwBytes = dwTotalBytes;    // Read remaining bytes
        
        // 2. Decrease remaining bytes counter
        scan->sParam.Size.dwTotalBytes -= dwBytes;
        
        // 3. Skip dark/blank lines if needed
        while (scan->bLinesToSkip > 0) {
            usb_ScanReadImage(dev, buffer, skipBytes);
            scan->bLinesToSkip--;
        }
        
        // 4. Read actual image data
        success = usb_ScanReadImage(dev, scan->pbGetDataBuf, dwBytes);
        
        if (!success) return 0;
    }
    
    return 1;  // Success
}
```

**Key Details:**
- Reads in **chunks** (e.g., multiple scan lines at once)
- Skips dark/damaged lines from beginning of scan
- Manages DRAM buffer on scanner (Limited DRAM space)
- Returns total lines successfully read

### Function 3.2: `usb_ScanReadImage()` - USB Transfer (plustek-usbscan.c:1494)

This function **executes the actual USB read** from scanner:

```c
SANE_Bool usb_ScanReadImage(Plustek_Device *dev, void *pBuf, u_long dwSize)
{
    u_char *regs = dev->usbDev.a_bRegs;  // Hardware registers
    SANE_Status res;
    
    // 1. First read: check if scanner has data ready
    if (m_fFirst) {
        m_fFirst = SANE_FALSE;
        
        // Wait until scanner has data in DRAM buffer
        if (!usb_IsDataAvailableInDRAM(dev)) {
            DBG(_DBG_ERROR, "Nothing to read...\n");
            return SANE_FALSE;  // Scanner not ready
        }
        
        // Restore fast-forward speed setting
        sanei_lm983x_write(dev->fd, 0x48, &regs[0x48], 2, SANE_TRUE);
    }
    
    // 2. Read image data FROM scanner DRAM
    //    Register 0x00 = data read port
    //    pBuf = destination buffer in host memory
    //    dwSize = number of bytes to read
    res = sanei_lm983x_read(dev->fd, 0x00, (u_char *)pBuf, dwSize, SANE_FALSE);
    
    // 3. Check for cancel/ESC button press
    if (usb_IsEscPressed()) {
        return SANE_FALSE;
    }
    
    // 4. Return result
    if (SANE_STATUS_GOOD == res) {
        return SANE_TRUE;   // Data read successfully
    } else {
        DBG(_DBG_ERROR, "usb_ScanReadImage() failed\n");
        return SANE_FALSE;  // Read error
    }
}
```

**Key Details:**
- Calls `sanei_lm983x_read()` with register **0x00** (data port)
- Reads **dwSize** bytes
- Checks if scanner has image data ready in DRAM
- Checks for user cancel button

### Function 3.3: `sanei_lm983x_read()` - Vendor-Specific Command

This is a **macro** defined in plustek-usbio.c that wraps the low-level command:

```c
// From plustek-usbio.c:85
#define _UIO(x) x

// Actually calls:
sanei_lm983x_read(fd, 0x00, buffer, bytes, SANE_FALSE)

// Which translates to a USB command that tells scanner:
// Command: LM9832 READ
// Address: 0x00 (data register)
// Size: bytes to read
// Block: SANE_FALSE (non-blocking)
```

---

## 4. USB Layer: `sanei_lm983x_read()` Details

The LM9832 is the **ISP controller chip** inside the scanner. The function sends commands to this chip:

### Command Structure

```
USB CONTROL TRANSFER (from host to scanner)
├─ Command ID: LM9832 "Read Register"
├─ Register Address: 0x00 (data from DRAM)
├─ Size: Number of bytes to read
└─ Endpoint: Bulk IN (USB endpoint for receiving data)

THEN

USB BULK TRANSFER (from scanner to host)
└─ Receives raw image bytes in pBuf
```

### Data Flow

```
Scanner LM9832 Chip
├─ CIS Sensor → A/D Converter
├─ Digital Image Data
├─ Stored in Scanner's DRAM Buffer
│
└─ USB Controller
   └─ Receives READ command on USB
        └─ Reads from DRAM
        └─ Sends bytes over USB BULK IN
           └─ Host receives via sanei_usb_read_bulk()
              └─ Stored in Host Buffer (pBuf)
```

---

## 5. Data Format Received from Scanner

### Raw Data From CIS Sensor

The Canon CanoScan LiDE 25 uses a **CIS (Contact Image Sensor)**:

```
CIS Sensor Output (for typical RGB scan):
├─ Red channel: 8 bits/pixel
├─ Green channel: 8 bits/pixel  
├─ Blue channel: 8 bits/pixel
│
└─ Bytes per pixel: 3 (RGB)
   └─ Example line: [R1 G1 B1 R2 G2 B2 R3 G3 B3 ...]

For Greyscale:
└─ 1 byte/pixel
   └─ Example line: [L1 L2 L3 L4 L5 ...]

Scan Parameters (from plustek.h):
├─ Default Resolution: 50-1200 DPI
├─ Max Scan Area: 216mm × 297mm (A4)
├─ Color Depth: 8-bit or 16-bit per channel
└─ Bytes per line calculated as:
    Bytes = (width_in_pixels * color_depth_bytes)
```

### Example Calculation

```c
Width requested: 100mm at 300 DPI
= (100mm / 25.4mm-per-inch) * 300 DPI
= 3.94 inches * 300 pixels/inch
= 1181 pixels

For RGB:
Bytes per line = 1181 pixels * 3 bytes = 3543 bytes

For 16-bit greyscale:
Bytes per line = 1181 pixels * 2 bytes = 2362 bytes
```

---

## 6. Buffer Management

### Scanner Side (DRAM Buffer)

The scanner has **limited onboard DRAM** (typically 512KB - 2MB):

```c
pl = dev->usbDev.a_bRegs[0x4e] * hw->wDRAMSize/128;
// Calculates available DRAM lines
```

**Strategy**: Read data in chunks so DRAM doesn't overflow

### Host Side (Plustek_Scanner)

```c
// In local_sane_start():
s->buf = malloc(s->params.lines * s->params.bytes_per_line);

// Example for 1200 DPI A4 scan (full color)
// Pixels per line: ~4700
// Bytes per line: 14100 (4700 * 3 for RGB)
// Lines: ~4700 (for A4 height)
// Total buffer: 66MB

// But we read in smaller chunks via dwBytesScanBuf
scan->dwBytesScanBuf = 65536;  // 64KB chunks
```

---

## 7. Complete Data Reception Sequence

```
┌─────────────────────────────────────────────────────────────────┐
│ 1. User calls sane_start()                                      │
│    └─> Opens USB device                                         │
│    └─> Configures scanner parameters                           │
│    └─> Starts scan on hardware                                  │
│    └─> Forks reader process                                    │
└─────────────────────────────────────────────────────────────────┘
                           ↓
┌─────────────────────────────────────────────────────────────────┐
│ 2. Reader Process Loop                                          │
│    While (scan not complete):                                   │
│    ┌─ Calculates chunk size to read (limited by scanner DRAM)  │
│    ├─ Calls usb_ReadData()                                     │
│    └─ Reads up to 64KB of image data                           │
└─────────────────────────────────────────────────────────────────┘
                           ↓
┌─────────────────────────────────────────────────────────────────┐
│ 3. usb_ReadData() - Main Data Pump                              │
│    For each chunk:                                              │
│    ├─ Calculates bytes to read (remaining total)               │
│    ├─ Skips damaged lines if configured                        │
│    └─ Calls usb_ScanReadImage() to get raw bytes              │
└─────────────────────────────────────────────────────────────────┘
                           ↓
┌─────────────────────────────────────────────────────────────────┐
│ 4. usb_ScanReadImage() - USB Transaction                        │
│    ├─ Checks scanner DRAM for data ready                       │
│    ├─ Calls sanei_lm983x_read(fd, 0x00, buffer, size)         │
│    │  (Register 0x00 = data port in LM9832 chip)              │
│    └─ Raw bytes now in buffer                                  │
└─────────────────────────────────────────────────────────────────┘
                           ↓
┌─────────────────────────────────────────────────────────────────┐
│ 5. sanei_lm983x_read() - Sends USB Commands                     │
│    ├─ Tells scanner: "Send me bytes from register 0x00"       │
│    └─ libusb transfers bytes over USB BULK IN endpoint        │
└─────────────────────────────────────────────────────────────────┘
                           ↓
┌─────────────────────────────────────────────────────────────────┐
│ 6. USB Hardware Layer                                           │
│    Scanner:                    Host:                            │
│    ├─ LM9832 reads from DRAM  ├─ libusb_bulk_transfer()       │
│    ├─ Sends over USB          ├─ Receives bytes               │
│    └─ (CIS data stream)       └─ Stores in pBuf               │
└─────────────────────────────────────────────────────────────────┘
                           ↓
┌─────────────────────────────────────────────────────────────────┐
│ 7. Reader Process Writes to Pipe                                │
│    write(s->w_pipe, data, bytes_read)                          │
│    └─ Makes data available to main application via IPC pipe   │
└─────────────────────────────────────────────────────────────────┘
                           ↓
┌─────────────────────────────────────────────────────────────────┐
│ 8. Application calls sane_read()                                │
│    read(s->r_pipe, data, max_length)                           │
│    └─ Returns image bytes to application                       │
│    └─ Application saves as .pnm, .tiff, etc.                  │
└─────────────────────────────────────────────────────────────────┘
```

---

## 8. Key Data Structures

### ScanDef (Scan Definition)

```c
typedef struct {
    SANE_Int dwTotalBytes;           // Total bytes to read
    SANE_Int dwPhyBytes;             // Physical bytes per line
    SANE_Int dwLinesToProcess;       // Lines left to process
    SANE_Int bLinesToSkip;           // Lines to skip (dark strip)
    u_char *pbGetDataBuf;            // Buffer to store data
    SANE_Int dwBytesScanBuf;         // Size of scan buffer (64KB)
    SANE_Int dwLinesScanBuf;         // Lines per buffer
} ScanDef;
```

### ImgDef (Image Definition)

```c
typedef struct {
    struct {
        SANE_Int x, y;      // Pixels per inch (DPI)
    } xyDpi;
    
    struct {
        u_long x, y;        // Top-left corner
        u_long cx, cy;      // Width, Height in pixels
    } crArea;
    
    u_short wDataType;      // RGB, GRAY, etc.
    u_long dwFlag;          // SCANDEF_Calibration, etc.
} ImgDef;
```

---

## 9. Data Reception Summary

| Layer | Function | Action | Buffer |
|-------|----------|--------|--------|
| **Application** | `sane_read()` | Requests image bytes | Reads from IPC pipe |
| **Main Process** | `sane_read()` | IPC from child | Via pipe to app buffer |
| **Reader Process** | `reader_process()` | Manages scan loop | Writes to pipe |
| **Backend** | `usb_ReadData()` | Chunks data reads | 64KB chunks |
| **Backend** | `usb_ScanReadImage()` | Executes USB read | Register 0x00 |
| **SANEI** | `sanei_lm983x_read()` | Low-level USB cmd | libusb transfer |
| **USB** | `libusb_bulk_transfer()` | Receives bytes | Host memory |
| **Hardware** | LM9832 Chip | Reads scanner DRAM | USB endpoint |
| **Hardware** | CIS Sensor | Captures image | Scanner DRAM |
| **Physical** | CIS Sensor array | Detects light | Raw pixel data |

---

## 10. Data Reception Parameters

### For Canon CanoScan LiDE 25

```
USB Device: Canon CanoScan LiDE 25
├─ Vendor ID: 0x04a9 (Canon)
├─ Product ID: 0x2220
├─ ISP Chip: LM9832
├─ Sensor: CIS (Contact Image Sensor)
├─ Max Resolution: 1200 DPI
├─ Max Scan Area: 216mm × 297mm
│
└─ USB Bulk Transfer Details:
   ├─ Endpoint: Bulk IN (data from scanner)
   ├─ Max Packet Size: 64KB per transfer
   ├─ Typical Speed: ~10-20 MB/s
   │
   └─ Data Format:
      ├─ Color: RGB (3 bytes/pixel)
      ├─ Greyscale: 1 byte/pixel  
      └─ At 1200 DPI A4 full color: ~66MB total
```

---

## Key Insight

**How data actually flows:**

1. **Sensor captures** → Analog light to digital (A/D converter)
2. **Data accumulates** → Stored in scanner's DRAM buffer
3. **Host requests** → "Send register 0x00" command via USB
4. **Scanner sends** → Bytes from DRAM over USB BULK IN
5. **Host receives** → libusb stores in host buffer
6. **Chunks organized** → Multiple chunks until full image
7. **Data delivered** → Through IPC pipe to application
8. **Application saves** → As PNM/TIFF image file

The entire process is **non-blocking** - the main application process remains responsive while a child process quietly reads data chunk-by-chunk in the background!
