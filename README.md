# 8051 Servo Motor Control Module

## Overview
An embedded systems project utilizing the 8051 Microcontroller (MCU) to precisely control a servo motor. The system allows users to select from four different speed modes using a 4x4 keypad, while tracking operation cycles on a 7-segment display. The software architecture heavily emphasizes non-blocking code, utilizing memory flags, breakable delays, and hardware interrupts to ensure immediate system responsiveness.

## Key Features
* **Dynamic LCD Interface:** Displays speed options (0, 1, 2, 3), confirmation prompts, and real-time running status. Screen refreshes are carefully managed by a `UI_DIRTY` memory flag to prevent display flickering.
* **Multi-Speed PWM Control:** Uses Timer 0 to generate PWM pulses, moving the motor back and forth with predefined wait times ranging from 1 second (Speed 3) to 3 seconds (Speed 0).
* **Hardware Interrupts:** * **Emergency Stop:** Triggered via a push button (`INT0` at `ORG 0003H`), this instantly clears the `MOTOR_EN` flag to halt all motor operations.
  * **System Reset:** Triggered via `INT1` (`ORG 0013H`), this updates the `UI_STATE` to return to the main menu without stopping a currently running motor cycle.
* **Cycle Tracking:** A multiplexed 7-segment display actively counts up to 10 completed back-and-forth motor cycles.
* **Non-Blocking Architecture:** Features a rapid keypad scan that returns `#0FFH` if no key is pressed, alongside breakable motor delays that instantly abort if an interrupt is triggered.

## Hardware Map
The module interfaces with several peripherals on the 8051 development board:
* **4x4 Keypad:** Connected to port `P1` for speed selection.
* **LCD Display:** Data lines connected to `P0`, with control lines on `P3.0`, `P3.1`, and `P3.4`.
* **7-Segment Display:** Data connected to `P2`, with multiplexing controlled via `P3.6` and `P3.7`.
* **Servo Motor:** Receives PWM signals directly from `P3.5`.
* **Push Buttons:** Connected to `P3.2` and `P3.3` for hardware interrupts.
