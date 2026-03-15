# How Custom Scanner Controls Work - Complete Guide

## Overview of the Modification

This code example shows how to add **handheld mode** to the scanner - essentially converting it from a flatbed (motor moves paper) to a handheld input (user manually moves the scanner).

The modification was inserted in `usb_ScanBegin()` - the function that starts a scan. This is the **critical point** where you have access to all the hardware registers and can inject custom commands.

---

## The Pattern: How Scanner Commands Are Sent

### Three-Step Command Pattern

```c
// 1. PREPARE: Modify registers (hardware configuration)
regs[0x45] = regs[0x45] & ~0x10;  // Bitwise operation to set specific bits

// 2. EXECUTE: Send command to hardware via LM9832
usbio_WriteReg(dev->fd, 0x45, regs[0x45]);  // Write register to scanner

// 3. VERIFY: Check for errors
if (!usbio_WriteReg(...)) {
    return SANE_FALSE;  // Abort if command failed
}
```

---

## The Handheld Mode Modification Explained

### What It Does

Converts the scanner for handheld mode by:
1. **Moving the sensor to center** - Positions the imager at a known location
2. **Restoring scan parameters** - Re-applies the correct timing registers
3. **Disabling motor power** - Cuts power to the stepper to allow manual movement

### Step 1: Move Sensor to Middle

```c
usb_ModuleMove(dev, MOVE_Forward, 2100UL)
```

**What this does:**
- Sends motor movement command (2100 steps forward)
- Changes registers: 0x08, 0x48, 0x49 (fast-feed mode registers)
- Positions the CIS sensor array in the middle of the scan bed

**Why needed for handheld:**
- Known starting position for manual scanning
- Centers the optical path

**Register changes made internally:**
```
Register 0x08  = MCLK Divider (motor timing)
Register 0x48  = Fast Feed Step Size (high byte)
Register 0x49  = Fast Feed Step Size (low byte)
```

### Step 2: Restore Scan Parameters

```c
usb_SetScanParameters(dev, m_pParam)
```

**Why this is critical:**
- `usb_ModuleMove()` changed motor-specific registers to "fast feed" mode
- But we need "scan" mode registers for actual image capture
- This function **recalculates and rewrites** all the timing parameters

**What gets restored:**

```c
// From usb_SetScanParameters():

pParam->PhyDpi.x = usb_SetAsicDpiX( dev, pParam->UserDpi.x );      // Horizontal DPI
pParam->PhyDpi.y = usb_SetAsicDpiY( dev, pParam->UserDpi.y );      // Vertical DPI
usb_SetColorAndBits( dev, pParam );                                 // Color mode (RGB/Gray)
usb_GetLineLength ( dev, pParam );                                  // Bytes per line
usb_GetStepSize   ( dev, pParam );                                  // Motor step timing
usb_GetMCLKDivider( dev, pParam );                                  // Master clock divider
usb_GetMotorParam ( dev, pParam );                                  // PWM settings

// Then writes ALL registers:
sanei_lm983x_write( dev->fd, 0x03, &regs[0x03], 3, SANE_TRUE);    // Batch write
sanei_lm983x_write( dev->fd, 0x08, &regs[0x08], 0x7f-0x08+1, SANE_TRUE); // Write 0x08-0x7f
```

### Step 3: Disable Motor Power

```c
usbio_WriteReg(dev->fd, 0x45, regs[0x45] & ~0x10)
```

**What this does:**

```
Register 0x45 = Motor Control Register

Bit layout:
┌─────────────────────────────────────┐
│ 7 6 5 4 3 2 1 0                     │
├─────────────────────────────────────┤
│       │ ↑                           │
│       └─ Bit 4 = Motor Enable       │
│          1 = Motor ON               │
│          0 = Motor OFF              │
└─────────────────────────────────────┘

Operation: regs[0x45] & ~0x10
           = regs[0x45] AND (NOT 0x10)
           = Clear bit 4 (Motor Enable)
           = Motor OFF
```

**Why this enables handheld:**
- Motor is disabled → No automatic paper feed
- CIS sensor still works → Captures light
- User manually moves the scanner → Creates the scanning motion

---

## Register Reference: Key Scanner Commands

### Motor Control (Register 0x45)

```c
// Enable motor
regs[0x45] |= 0x10;           // Set bit 4
usbio_WriteReg(dev->fd, 0x45, regs[0x45]);

// Disable motor (handheld mode)
regs[0x45] &= ~0x10;          // Clear bit 4
usbio_WriteReg(dev->fd, 0x45, regs[0x45]);
```

### Sensor Control (Registers 0x0b-0x18)

Controls the CIS sensor itself:

```c
// From usb_ResetRegisters() in plustek-usbhw.c:

memcpy( regs+0x0b, &hw->bSensorConfiguration, 4 );     // 0x0b-0x0e: Sensor type
memcpy( regs+0x0f, &hw->bReg_0x0f_Color, 10 );         // 0x0f-0x18: CIS settings

// What these control:
// - A/D converter bit depth (8-bit vs 16-bit)
// - Pixel clock frequency
// - Integration time (exposure)
// - Channel configuration (RGB vs Grayscale)
```

### Data Port (Register 0x00) - READ ONLY

```c
// Request image data from scanner DRAM
sanei_lm983x_read(dev->fd, 0x00,   // Data port register
                   buffer,          // Host memory to receive data
                   size,            // Bytes to read
                   SANE_FALSE);     // Non-blocking
```

### Master Clock Divider (Register 0x08)

Controls pixel timing:

```c
// From usb_GetMCLKDivider():
regs[0x08] = (u_char)((m_dMCLKDivider - 1) * 2);
sanei_lm983x_write(dev->fd, 0x08, &regs[0x08], 1, SANE_TRUE);

// This sets how fast pixels are read:
// - Lower value = faster pixel clock = shorter exposure
// - Higher value = slower pixel clock = longer exposure
```

### Fast Feed Step Size (Registers 0x48-0x49)

Controls motor speed for positioning:

```c
// From usb_PresetStepSize():
regs[0x48] = _HIBYTE(ssize);    // High byte
regs[0x49] = _LOBYTE(ssize);    // Low byte
sanei_lm983x_write(dev->fd, 0x48, &regs[0x48], 2, SANE_TRUE);

// Used by usb_ModuleMove() for positioning moves
```

---

## How to Make Your Own Commands

### Pattern 1: Simple Register Write (One-Time Command)

```c
// Example: Set brightness to maximum
// Suppose brightness is in register 0x60

u_char brightness_value = 255;  // 255 = maximum brightness

if (!usbio_WriteReg(dev->fd, 0x60, brightness_value)) {
    DBG(_DBG_ERROR, "Failed to set brightness\n");
    return SANE_FALSE;
}
```

### Pattern 2: Bit Manipulation (Enable/Disable Feature)

```c
// Example: Enable lamp

// Get current register value
u_char *regs = dev->usbDev.a_bRegs;

// Set specific bit (bit 0 = lamp enable)
regs[0x46] |= 0x01;   // Set bit 0 to 1

// Write to scanner
if (!usbio_WriteReg(dev->fd, 0x46, regs[0x46])) {
    DBG(_DBG_ERROR, "Failed to enable lamp\n");
    return SANE_FALSE;
}
```

### Pattern 3: Batched Register Write (Multiple Parameters)

```c
// Example: Set color mode

u_char *regs = dev->usbDev.a_bRegs;

// Modify multiple registers
regs[0x26] = 0x07;      // Color mode select
regs[0x0f] = 0x12;      // CIS config for RGB
regs[0x10] = 0x34;
regs[0x11] = 0x56;

// Write them all in one batch
if (!sanei_lm983x_write(dev->fd, 0x0f, &regs[0x0f], 10, SANE_TRUE)) {
    DBG(_DBG_ERROR, "Failed to set color mode\n");
    return SANE_FALSE;
}
```

### Pattern 4: Sequential Motor Movement

```c
// Example: Move sensor for handheld calibration

if (!usb_ModuleMove(dev, MOVE_Forward, 500UL)) {
    DBG(_DBG_ERROR, "Motor move failed\n");
    return SANE_FALSE;
}

// Optional: Delay for mechanical settling
usleep(50000);  // 50ms delay

// Then send next command
if (!usb_ModuleMove(dev, MOVE_Forward, 1000UL)) {
    DBG(_DBG_ERROR, "Second move failed\n");
    return SANE_FALSE;
}
```

---

## The Complete Command Flow for Handheld Mode

```
usb_ScanBegin()  (Entry point for scan start)
│
├─ Check: Is this a real scan? (pParam->bCalibration == PARAM_Scan)
│
├─ Move 1: Position sensor to center (2100 steps)
│          └─> usb_ModuleMove(dev, MOVE_Forward, 2100UL)
│              ├─ Sets 0x08 (MCLK) = fast feed mode
│              ├─ Sets 0x48-0x49 (fast step size)
│              └─ Drives motor 2100 steps forward
│
├─ Restore: Recalculate all scan-mode timing
│           └─> usb_SetScanParameters(dev, m_pParam)
│               ├─ usb_GetLineLength() → calculates line timing
│               ├─ usb_GetStepSize() → recalculates step timing
│               ├─ usb_GetMCLKDivider() → recalculates MCLK
│               └─ Writes registers 0x03-0x7f with correct values
│
├─ Disable: Cut motor power so user can move manually
│           └─> usbio_WriteReg(dev->fd, 0x45, regs[0x45] & ~0x10)
│               └─ Clear bit 4 of register 0x45 (Motor Enable)
│
└─ Continue: Start image capture with suspended motor
             └─> usbio_WriteReg(dev->fd, 0x07, 3)
                 └─ Begin reading image data
```

---

## Key Insights for Custom Commands

### 1. **Register Shadow Copies Matter**

```c
u_char *regs = dev->usbDev.a_bRegs;  // Local copy of all registers

// ALWAYS modify the shadow first
regs[0x45] &= ~0x10;  // Modify shadow

// THEN write to hardware
usbio_WriteReg(dev->fd, 0x45, regs[0x45]);  // Send to LM9832

// Why? Hardware can change externally, shadow keeps our intent
```

### 2. **Order Matters**

```c
// CORRECT: Move → Restore Settings → Disable Motor
usb_ModuleMove(dev, MOVE_Forward, 2100UL);     // Changes registers
usb_SetScanParameters(dev, m_pParam);          // Restores them
usbio_WriteReg(dev->fd, 0x45, ...);            // Final adjustment

// WRONG: This would overwrite your motor disable!
usbio_WriteReg(dev->fd, 0x45, ...);            // Motor OFF
usb_SetScanParameters(dev, m_pParam);          // Sets 0x45 back to ON!
```

### 3. **Always Check Return Values**

```c
// GOOD: Verify each command
if (!usb_ModuleMove(dev, MOVE_Forward, 2100UL)) {
    DBG(_DBG_ERROR, "Failed to move\n");
    return SANE_FALSE;  // Abort if command fails
}

// BAD: Ignore errors and continue
usb_ModuleMove(dev, MOVE_Forward, 2100UL);  // Might have failed!
usb_SetScanParameters(dev, m_pParam);       // Proceeds anyway
```

### 4. **Use Microsecond Delays Between Commands**

```c
// Safe sequence with settling time
usb_ModuleMove(dev, MOVE_Forward, 2100UL);
usleep(50000);  // 50ms for mechanical settling

usb_SetScanParameters(dev, m_pParam);
usleep(100);    // 100us for register propagation

usbio_WriteReg(dev->fd, 0x45, ...);
```

---

## Practical Examples for Your Scanner

### Example 1: Custom Brightness Control

```c
static SANE_Status custom_set_brightness(Plustek_Device *dev, int brightness)
{
    // brightness: 0-255
    u_char *regs = dev->usbDev.a_bRegs;
    
    DBG(_DBG_INFO, "Setting brightness to %d\n", brightness);
    
    // Brightness might be in register 0x60 (example)
    regs[0x60] = (u_char)brightness;
    
    if (!usbio_WriteReg(dev->fd, 0x60, regs[0x60])) {
        DBG(_DBG_ERROR, "Failed to set brightness\n");
        return SANE_STATUS_IO_ERROR;
    }
    
    return SANE_STATUS_GOOD;
}
```

### Example 2: Custom Motor Speed Control

```c
static SANE_status custom_set_motor_speed(Plustek_Device *dev, double speed)
{
    // speed: 0.5 (slow) to 2.0 (fast)
    HWDef *hw = &dev->usbDev.HwSetting;
    u_char *regs = dev->usbDev.a_bRegs;
    u_short step_size;
    
    DBG(_DBG_INFO, "Setting motor speed to %.2f\n", speed);
    
    // Calculate new step size
    step_size = (u_short)(CRYSTAL_FREQ / (speed * 8.0 * 3 * hw->dMaxMotorSpeed * 4 * hw->wMotorDpi));
    
    regs[0x48] = _HIBYTE(step_size);
    regs[0x49] = _LOBYTE(step_size);
    
    if (!sanei_lm983x_write(dev->fd, 0x48, &regs[0x48], 2, SANE_TRUE)) {
        DBG(_DBG_ERROR, "Failed to set motor speed\n");
        return  SANE_STATUS_IO_ERROR;
    }
    
    return SANE_STATUS_GOOD;
}
```

### Example 3: Custom Integration Time (Exposure)

```c
static SANE_status custom_set_integration_time(Plustek_Device *dev, u_char ita)
{
    // ita: integration time adjust (0-255, higher = longer exposure)
    u_char *regs = dev->usbDev.a_bRegs;
    
    DBG(_DBG_INFO, "Setting integration time adjust to %u\n", ita);
    
    // Register 0x19 controls integration time
    regs[0x19] = ita;
    
    if (!usbio_WriteReg(dev->fd, 0x19, ita)) {
        DBG(_DBG_ERROR, "Failed to set integration time\n");
        return SANE_STATUS_IO_ERROR;
    }
    
    // If changing ITA, must recalculate step sizes
    usb_GetStepSize(dev, &dev->scanning.sParam);
    
    return SANE_STATUS_GOOD;
}
```

---

## Summary

**To make custom scanner commands:**

1. **Identify the register** that controls your feature (0x00-0x7f range)
2. **Modify the shadow copy** (`regs[]` array)
3. **Send via correct function:**
   - Single register: `usbio_WriteReg(fd, addr, value)`
   - Multiple registers: `sanei_lm983x_write(fd, addr, &regs[addr], count)`
4. **Always check for errors** and handle failures
5. **Understand dependencies** (e.g., changing speed needs step size recalc)
6. **Add debug output** so you can trace what happened

The handheld modification shows this perfectly: it uses existing functions (`usb_ModuleMove`, `usb_SetScanParameters`) which internally manipulate registers, proving that custom features are built from **combinations of basic register operations**.
