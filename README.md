# NanoRISCV-C2: Ultra-Compact 2-Stage RISC-V Core with a Hardware Performance Monitor

A small, readable **2-stage pipelined RV32I-subset core** written in Verilog, extended with a **hardware performance monitor (`PerfMonitor`)** that counts clock cycles and core events (instructions, branches, taken branches, loads, stores) so the core's real CPI can be measured on the RTL itself.

The project was built in two parts:

1. **NanoRISCV-C2**: the core, its testbenches, Vivado implementation results, and a 5,000-row instruction-trace dataset for CPI analysis.
2. **PerfMonitor**: hardware counters that watch the core without changing its datapath (practice project #15, *System Performance Monitor: Cycle & Event Tracker*).

> Developed by **Abhishek Soni**, B.Tech ECE, ABES Engineering College, Ghaziabad (VLSI project).

---

## Table of contents

1. [Highlights](#highlights)
2. [Architecture](#architecture)
3. [Repository structure](#repository-structure)
4. [The core in detail](#the-core-in-detail)
5. [The performance monitor in detail](#the-performance-monitor-in-detail)
6. [Test program and expected results](#test-program-and-expected-results)
7. [Verification](#verification)
8. [How to run](#how-to-run)
9. [Implementation results](#implementation-results)
10. [Dataset](#dataset)
11. [Design decisions and lessons learned](#design-decisions-and-lessons-learned)
12. [Known limitations](#known-limitations)
13. [Roadmap](#roadmap)
14. [AI assistance and acknowledgements](#ai-assistance-and-acknowledgements)
15. [License](#license)

---

## Highlights

- **Two pipeline stages**: Stage 1 fetches, Stage 2 decodes, executes, accesses memory and writes back. All execution is in one stage, so the core needs **no forwarding unit and no hazard-detection unit**.
- **One-cycle branch penalty**: a taken `BEQ` flushes the instruction fetched behind it, costing exactly one bubble.
- **`PerfMonitor`**: six 32-bit counters (cycles, instructions retired, branches, taken branches, loads, stores), sticky overflow flags, a start/stop `enable`, a synchronous `clear`, and a counter-select read-out that needs only 36 pins.
- **Self-checking testbenches**: a full-core testbench that prints CPI, and a standalone monitor testbench with 10 tests and 57 checks (all passing).
- **Implemented in Vivado** on a Kintex-7 (`xc7k70tfbv676-1`), with timing met at a 20 ns (50 MHz) clock.
- **Open ISA, no third-party IP**: RISC-V is an open standard and every module is plain Verilog.

---

## Architecture

![NanoRISCV-C2 with PerfMonitor](docs/NanoRISCV_C2_PerfMonitor_Architecture.png)

**Reading the diagram**

| Colour | Meaning |
|---|---|
| Thick black | 32-bit data bus |
| Thin blue | control signal |
| Green dashed | signal tapped (read-only) by the `PerfMonitor` |
| Green box | new hardware (`PerfMonitor` and the `ex_valid` bit) |

**Data flow in one paragraph.** The program counter addresses the instruction memory. The fetched instruction and its PC are stored in the IF/EX pipeline register. In Stage 2 the control unit decodes the opcode, the register file supplies operands, the ALU computes a result (or an address), the data memory serves loads and stores, and a mux chooses what is written back. For a `BEQ`, the ALU subtracts the operands; if the result is zero, `take_branch = Branch AND Zero` redirects the PC to `ex_pc + imm_ext` and flushes the pipeline register.

---

## Repository structure

> Adjust the paths below to match your repository.

```
NANORISCV-C2/
├── rtl/
│   ├── NanoRISCV_C2.v        top level (core + monitor)
│   ├── ProgramCounter.v
│   ├── PC_Adder.v
│   ├── InstructionMemory.v   128 x 32, holds the test program
│   ├── Pipeline_Reg.v        IF/EX register with ex_valid
│   ├── ControlUnit.v
│   ├── RegisterFile.v
│   ├── ImmGen.v
│   ├── ALU.v
│   ├── DataMemory.v          256 x 32
│   ├── Mux2to1.v
│   └── PerfMonitor.v         hardware performance counters
├── tb/
│   ├── tb_NanoRISCV_C2.v     full-core test, prints counters and CPI
│   └── tb_PerfMonitor.v      standalone, self-checking monitor test
├── constraints/
│   └── timing.xdc
├── dataset/
│   ├── dataset_5000.csv      instruction-trace dataset
│   ├── data_dictionary.csv
│   └── gen_traces.py         generator for the extra dataset rows
├── docs/
│   ├── NanoRISCV_C2_PerfMonitor_Architecture.png
│   └── (waveforms, Vivado report screenshots)
└── README.md
```

---

## The core in detail

### Modules

| Module | Role |
|---|---|
| `ProgramCounter` | Holds the current instruction address; resets to 0 on an active-high asynchronous reset |
| `PC_Adder` | Computes `PC + 4` |
| `InstructionMemory` | 128 x 32-bit, word-aligned, asynchronous read; pre-initialised with the test program (all other words are NOPs) |
| `Pipeline_Reg` | IF/EX register. Holds `ex_pc`, `ex_instruction` and `ex_valid`; loads a NOP (`0x00000013`) on reset and on flush |
| `ControlUnit` | Decodes the 7-bit opcode into `RegWrite`, `ALUSrc`, `MemRead`, `MemWrite`, `MemtoReg`, `Branch` and a 4-bit `ALUOp` |
| `RegisterFile` | 32 x 32-bit, two asynchronous read ports, one synchronous write port, `x0` hard-wired to 0 |
| `ImmGen` | Sign-extended immediates for I, S, B, U and J formats |
| `ALU` | `ADD`, `SUB`, `OR`, `XOR`, `SLT`, `SLL`, `SRL` plus a `Zero` flag |
| `DataMemory` | 256 x 32-bit, synchronous write, asynchronous read, byte address converted to word index |
| `Mux2to1` | 32-bit 2-to-1 multiplexer (ALU source, write-back, and so on) |
| `NanoRISCV_C2` | Top level; connects everything and instantiates the monitor. `debug_out` shows the ALU result |

### Instructions executed by the hardware

| Instruction | Opcode | Control behaviour |
|---|---|---|
| R-type (executes as `ADD`) | `0110011` | `RegWrite`, `ALUOp = 0010` |
| `ADDI` | `0010011` | `RegWrite`, `ALUSrc` |
| `LW` | `0000011` | `ALUSrc`, `MemRead`, `MemtoReg`, `RegWrite` |
| `SW` | `0100011` | `ALUSrc`, `MemWrite` |
| `BEQ` | `1100011` | `Branch`, `ALUOp = 0001` (subtract) |

### Pipeline behaviour

- **Normal flow:** one instruction completes per clock, so CPI is 1.
- **Taken `BEQ`:** `take_branch = Branch AND Zero`. On the next clock edge the PC loads `ex_pc + imm_ext` and the pipeline register is loaded with a NOP and `ex_valid = 0`. That wasted slot is a **bubble**.
- **No hazards to resolve:** operands are read, the ALU runs, memory is accessed and the register is written in the same stage, so a result is always available to the next instruction.

---

## The performance monitor in detail

### What it does

Real CPUs include hardware counters (RISC-V defines `cycle` and `instret`). `PerfMonitor` does the same for NanoRISCV-C2: it counts clock cycles and a few events, so **CPI = cycles / instructions** can be measured directly from the RTL.

### Events and where they come from

| Counter | Counts one when... | Source in the core |
|---|---|---|
| `cycle_cnt` | every clock edge while enabled | clock |
| `instr_cnt` | a real instruction is in Stage 2 | `ex_valid` |
| `branch_cnt` | a `BEQ` is in Stage 2 | `Branch` from the control unit |
| `taken_cnt` | that `BEQ` is taken (also a flush) | `take_branch` |
| `load_cnt` | an `LW` is in Stage 2 | `MemRead` |
| `store_cnt` | an `SW` is in Stage 2 | `MemWrite` |

Why `ex_valid` exists: a flushed bubble is loaded as a NOP, which looks the same as a real `addi x0, x0, 0` from the program. The one-bit `ex_valid` flag in `Pipeline_Reg` (0 for reset or flush, 1 otherwise) lets the monitor tell them apart. It is the **only change made to the core**.

### Ports

| Port | Direction | Description |
|---|---|---|
| `clk`, `reset` | in | Same clock and asynchronous reset as the core |
| `enable` | in | Counters run only while 1 (measurement window) |
| `clear` | in | Synchronous clear of all counters and overflow flags |
| `instr_valid`, `is_branch`, `branch_taken`, `is_load`, `is_store` | in | Event taps from Stage 2 |
| `sel[2:0]` | in | Chooses which counter appears on `data` |
| `data[31:0]` | out | Selected counter value |
| `overflow` | out | Sticky; 1 if any counter has wrapped around |

### Behaviour rules

- **Priority:** `reset` > `clear` > `enable`.
- **Overflow:** each counter has a sticky flag that is set when it wraps from `FFFFFFFF` to 0. It stays set until `reset` or `clear`.
- **Read-out:** the output mux is combinational, so changing `sel` changes `data` immediately.

### Read-out map

| `sel` | `data` shows |
|---|---|
| 0 | cycles |
| 1 | instructions retired |
| 2 | branches (BEQ executed) |
| 3 | branches taken (flushes) |
| 4 | loads |
| 5 | stores |
| 6 | overflow flags `{26'd0, ovf[5:0]}` |
| 7 | 0 |

### Using it from the top level

```verilog
// start measuring
perf_enable = 1;
// ... run the program ...
perf_enable = 0;

// read a counter
perf_sel = 3'd0;  #1;  cycles = perf_data;
perf_sel = 3'd1;  #1;  instrs = perf_data;
// CPI = cycles / instrs
```

Top-level monitor ports: `perf_enable`, `perf_clear`, `perf_sel[2:0]`, `perf_data[31:0]`, `perf_overflow`.

---

## Test program and expected results

The test program (preloaded in `InstructionMemory.v`) sums 5 + 4 + 3 + 2 + 1 with a loop:

| Address | Machine code | Instruction | Meaning |
|---|---|---|---|
| `0x00` | `00500093` | `ADDI x1, x0, 5` | counter = 5 |
| `0x04` | `00000113` | `ADDI x2, x0, 0` | sum = 0 |
| `0x08` | `00110133` | `ADD  x2, x2, x1` | loop: sum += counter |
| `0x0C` | `FFF08093` | `ADDI x1, x1, -1` | counter-- |
| `0x10` | `00008463` | `BEQ  x1, x0, +8` | counter == 0 ? exit |
| `0x14` | `FE000AE3` | `BEQ  x0, x0, -12` | always taken: back to loop |
| `0x18` | `00202023` | `SW   x2, 0(x0)` | `mem[0]` = sum |
| `0x1C` | `00002183` | `LW   x3, 0(x0)` | `x3` = 15 |

**Expected counters** (measured from reset release until the `LW` finishes):

| Counter | Value |
|---|---|
| Cycles | 29 |
| Instructions | 23 |
| Branches (BEQ executed) | 9 |
| Branches taken | 5 |
| Loads / Stores | 1 / 1 |
| **CPI** | **29 / 23 = 1.26** |

**Where the 29 cycles come from**

| Phase | Cycles | Instructions |
|---|---|---|
| Start-up bubble after reset | 1 | 0 |
| `ADDI`, `ADDI` | 2 | 2 |
| Loop passes 1 to 4 (ADD, ADDI, BEQ not taken, BEQ taken, then 1 bubble) | 4 x 5 = 20 | 4 x 4 = 16 |
| Last pass (ADD, ADDI, BEQ taken, then 1 bubble) | 4 | 3 |
| `SW`, `LW` | 2 | 2 |
| **Total** | **29** | **23** |

The 6 lost cycles are 1 start-up bubble plus 5 flushes (one per taken branch), so `CPI = 1 + (flushes / instructions)` plus the start-up cycle. The program also leaves `mem[0] = 15` and `x3 = 15`.

---

## Verification

| Testbench | What it covers | Result |
|---|---|---|
| `tb_NanoRISCV_C2` | Runs the loop program, stops counting at `PC = 0x24`, prints all counters and CPI, checks `mem[0] = 15` and `x3 = 15`, then tests `perf_clear` | Matches the table above |
| `tb_PerfMonitor` | Monitor alone: reset, ignored events while disabled, a known event pattern, idle cycles, freeze on disable, clear overriding events, restart after clear, overflow, sticky flag, `sel = 7`, async reset | 10 tests, 57 checks, all pass |

`tb_PerfMonitor` is self-checking and ends with `ALL TESTS PASSED`. Set `test_id` in the waveform to see which test is running.

Expected `tb_NanoRISCV_C2` console output:

```
Cycles              = 29
Instructions        = 23
Branches (BEQ)      = 9
Branches taken      = 5
Loads / Stores      = 1 / 1
CPI x100            = 126
Overflow flag       = 0
mem[0] = 15 (expected 15), x3 = 15 (expected 15)
Cycles after clear  = 0 (expected 0)
```

### Waveforms

> Add your screenshots to `docs/` and update the file names below.

![Top-level waveform](docs/waveform_top.png)

*Core signals and monitor counters: `ex_valid` drops on every flush, `take_branch` pulses 5 times, and `cycle_cnt` / `instr_cnt` end at 29 / 23.*

![PerfMonitor testbench waveform](docs/waveform_perfmonitor_tb.png)

*Standalone monitor testbench, with `test_id` showing the active test.*

---

## How to run

### Vivado (GUI)

1. Create a project and pick a part (`xc7z020clg400-1` for the PYNQ-Z2, or `xc7k70tfbv676-1` as used for the results below).
2. Add everything in `rtl/` as **Design Sources**, `tb/` as **Simulation Sources**, and `constraints/timing.xdc` as the **Constraints** file.
3. Set `NanoRISCV_C2` as the design top and `tb_NanoRISCV_C2` as the simulation top (use `tb_PerfMonitor` to test the monitor alone).
4. Run **Behavioral Simulation** and read the Tcl console.
5. Run **Synthesis** and **Implementation** to get timing, utilisation and power.

Make sure there is only one copy of `Mux2to1.v` in the project.

### Command line (Icarus Verilog)

```bash
# full core with the monitor
iverilog -g2012 -o sim_core rtl/*.v tb/tb_NanoRISCV_C2.v
vvp sim_core

# monitor on its own
iverilog -g2012 -o sim_pm rtl/PerfMonitor.v tb/tb_PerfMonitor.v
vvp sim_pm
```

### Constraints (`timing.xdc`)

```tcl
create_clock -period 20.000 -name clk [get_ports clk]
set_input_delay  -clock clk 2.000 [get_ports {reset perf_enable perf_clear perf_sel[*]}]
set_output_delay -clock clk 2.000 [get_ports {debug_out[*] perf_data[*] perf_overflow}]
```

Pin locations (`PACKAGE_PIN`, `IOSTANDARD`) are not included yet; they are needed for a board build.

---

## Implementation results

### NanoRISCV-C2 core (Kintex-7 `xc7k70tfbv676-1`, Vivado, 20 ns clock)

Measured on the core before the monitor was added, running the 8-instruction test program.

| Metric | Value |
|---|---|
| Worst setup slack (WNS) | 3.510 ns (0 failing endpoints out of 1,886) |
| Worst hold slack (WHS) | 0.063 ns (0 failing endpoints out of 1,886) |
| Worst pulse-width slack | 9.090 ns |
| Estimated max clock | about 60.6 MHz (1 / (20 ns − 3.510 ns)) |
| LUTs | 429 of 41,000 (1.05%) |
| LUTRAM | 172 of 13,400 (1.28%) |
| Flip-flops | 33 of 82,000 (0.04%) |
| Block RAM / DSP | 0 / 0 |
| I/O pins | 34 of 300 (11.33%) |
| Total on-chip power | 0.084 W (0.002 W dynamic, 0.081 W device static) |

### Core + PerfMonitor

| Metric | Kintex-7 `xc7k70tfbv676-1` | PYNQ-Z2 `xc7z020clg400-1` |
|---|---|---|
| WNS / WHS | to be added | to be added |
| LUTs / LUTRAM / FFs | to be added | to be added |
| Power | to be added | to be added |

The monitor is expected to add about 200 flip-flops (six 32-bit counters plus overflow flags) and a small amount of logic; the measured overhead will be filled in after implementation.

---

## Dataset

`dataset/dataset_5000.csv` is a **synthetic** RISC-V instruction trace used to study cycles per instruction (CPI), branch behaviour and stalls.

| Item | Value |
|---|---|
| Rows / columns | 5,000 / 9 |
| Columns | `pc`, `instruction_hex`, `opcode`, `rs1`, `rs2`, `rd`, `cycles_taken`, `branch_taken`, `stall` |
| Opcode classes | ALU 41.7%, load/store 25.2%, branch 19.0%, jump 14.0% (target 40 / 25 / 20 / 15) |
| Mean CPI | 1.372 |
| Branch/jump taken rate | 26.1% |
| Stall rate | 6.5% |

- The first 500 rows were supplied with the project. The other 4,500 were generated with an AI tool using `dataset/gen_traces.py`, which produces valid RV32I encodings and a 2-stage pipeline timing model (`cycles_taken = 1 + branch_taken + stall cycles`).
- The supplied rows are internally inconsistent (for example, `instruction_hex` rarely matches the opcode), so the file is best read as synthetic data.
- The trace covers a wider opcode mix (including `SUB`, `AND`, `XOR`, `LUI` and `JAL`) than the subset the Verilog core executes today. It is used for instruction-level CPI analysis, not as a replay of the RTL.

---

## Design decisions and lessons learned

- **Why a read-out mux:** six 32-bit counters would need 192 output pins. One 32-bit `data` bus plus a 3-bit `sel` needs 36, which fits a real board.
- **Why `enable` and `clear`:** a real monitor needs a measurement window. The testbench enables counting at reset release and disables it when the program finishes.
- **Why `ex_valid`:** see above; without it the monitor cannot tell a flushed bubble from a real NOP.
- **The empty-design trap:** in the first implementation, the test program was injected by the testbench instead of being stored in the instruction memory. Vivado saw a memory full of NOPs and removed the whole core as constant logic (0 LUTs, no timing paths). Putting the program in the memory's `initial` block made it part of the synthesised design. Anything you want to keep through synthesis must influence an output.
- **Flush written as a clocked condition:** the pipeline register treats `flush` synchronously (`else if (flush)`), which matches simulation and hardware.

---

## Known limitations

- Only R-type (as `ADD`), `ADDI`, `LW`, `SW` and `BEQ` execute. There is no `JAL`, `LUI`, `BNE`, and `funct3`/`funct7` are not decoded, so `SUB`, `AND`, `OR`, `XOR`, `SLT`, `SLL` and `SRL` exist in the ALU but cannot be selected by instructions yet.
- No pipeline stalls exist, so there is no stall counter. CPI above 1 comes only from branch flushes and the start-up bubble.
- Instruction memory is 128 words and data memory is 256 words; there are no byte or half-word accesses.
- The program counter wraps after 128 words because the instruction memory uses 7 address bits.
- No board pin constraints yet.

---

## Roadmap

- [ ] Implement on the PYNQ-Z2 (pin constraints, and a clock source or divider suited to the board's clock)
- [ ] Add `funct3` / `funct7` decoding so the full ALU is reachable
- [ ] Add `JAL`, `LUI` and `BNE`
- [ ] Add a stall source (for example, a memory wait state) and a stall counter
- [ ] Snapshot register to read all counters at one instant
- [ ] Hardware CPI output (divider)
- [ ] Event masking and a threshold interrupt
- [ ] Memory-mapped register interface for the monitor
- [ ] Log a trace directly from the RTL testbench to replace the synthetic dataset

---

## AI assistance and acknowledgements

AI tools were used as helpers on this project: dataset generation (the extra 4,500 rows and `gen_traces.py`), review and debugging support, testbench and monitor development, and drafting documentation. All design decisions, code and results were reviewed and tested by the author.

RISC-V is an open standard instruction set architecture from RISC-V International. This project uses no third-party IP cores.

---

## License

Released under the MIT License. See `LICENSE`.
