# NanoRISCV-C2 Performance Monitor
**Hardware System Performance Monitor (Cycle & Event Tracker) for a 2-Stage RV32I RISC-V Core**

## Overview
This project implements a synthesizable, non-invasive **Hardware Performance Monitoring Unit (`PerfMonitor`)** in Verilog HDL and integrates it into the **NanoRISCV-C2** 2-stage pipelined RISC-V (RV32I) processor core.

Instead of estimating processor efficiency offline using software trace scripts, this design tracks clock cycles, retired instructions, branch behaviour, pipeline flushes, and memory operations directly in hardware in real time. The monitor taps Stage 2 (EX) control signals without modifying the processor's datapath, making it suitable for live profiling and embedded FPGA deployment on the **PYNQ-Z2 (Zynq-7020)** board.

---

## Key Features
* **6 Independent 32-Bit Hardware Counters:** Tracks total clock cycles, valid executed instructions, total branches, taken branches (flushes), memory loads, and memory stores.
* **Accurate Bubble Filtering:** Uses a dedicated `ex_valid` pipeline register flag so reset bubbles and branch-flush NOPs (`0x00000013`) are excluded from the instruction count, enabling exact hardware CPI calculation.
* **Sticky Overflow Detection:** Individual 6-bit overflow flags (`ovf[5:0]`) latch on any 32-bit counter wrap-around (`0xFFFFFFFF → 0x00000000`), combined into a single top-level `perf_overflow` status signal.
* **Deterministic Control Priority:** Asynchronous `reset` overrides synchronous `clear`, which overrides `enable` gating (`reset > clear > enable`).
* **Pin-Efficient Multiplexed Readout:** A 3-bit selector (`perf_sel[2:0]`) exposes all six counters and the overflow bitmask over a single 32-bit `perf_data` bus.
* **Non-Invasive Core Integration:** Observes Stage 2 signals passively with zero functional impact on instruction execution.

---

## Architecture & Integration

### System Block Diagram
```text
                    +-------------------------------------------------------+
                    |                     NanoRISCV_C2                      |
                    |                                                       |
   clk, reset ----->|  [ Stage 1: IF ] ---> [ IF/EX Reg ] ---> [ Stage 2: EX/MEM/WB ]
                    |    PC, Adder,          ex_pc,              CU, RegFile, ImmGen,
                    |    IMEM (128x32)       ex_instruction,     ALU, DMEM (256x32)
                    |                        ex_valid                 |
                    |                           |                     |
                    |                           |   ex_valid, branch, |
                    |                           |   take_branch,      |
                    |                           |   memread, memwrite |
                    |                           v                     v
                    |               +-----------------------------------+
 perf_enable ------>|               |            PerfMonitor            |-----> perf_data[31:0]
 perf_clear ------->|               |  6x 32-bit Counters + 6-bit OVF   |-----> perf_overflow
 perf_sel[2:0] ---->|               +-----------------------------------+
                    |                                                       |
                    +-------------------------------------------------------+-----> debug_out[31:0]
