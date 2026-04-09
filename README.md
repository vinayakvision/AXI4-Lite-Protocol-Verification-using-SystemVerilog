# AXI4-Lite Slave Memory Controller

**Author:** Vinayak Venkappa Pujeri (Vision)  
**Tool:** Cadence Xcelium / irun 15.20  
**Standard:** ARM IHI0022E — AXI4-Lite Protocol

---

## Overview

A fully synthesisable, spec-compliant AXI4-Lite slave implementing a 16-word
(64-byte) memory-mapped register bank. The design targets the 180 nm process
node via Cadence Genus/Innovus and is verified with a self-checking SystemVerilog
testbench that includes protocol assertions and functional coverage.

---

## Project Structure

```
axi4lite_slave/
├── rtl/
│   ├── axi4lite_if.sv       # Interface: signals + assertions + covergroup
│   └── axi4lite_slave.sv    # Synthesisable slave RTL
├── tb/
│   └── axi4lite_tb.sv       # Self-checking testbench (5 test cases)
├── Makefile
└── README.md
```

---

## Features

| Feature | Detail |
|---|---|
| Protocol | AXI4-Lite (ARM IHI0022E) |
| Data width | 32-bit |
| Address width | 32-bit |
| Memory | 16 × 32-bit (64 bytes), word-aligned |
| Write strobes | 4-bit `WSTRB` byte-enable (all combinations) |
| Error response | `SLVERR` (BRESP/RRESP = `2'b10`) on out-of-range access |
| Reset | Active-low synchronous-to-clock `ARESETn` |
| Handshake | Independent AW/W channels; WREADY gated on `aw_active` |

---

## Key Design Decisions

### Independent AW / W channel latching
The original naive implementation sampled `AWADDR` in the same clock edge that
it asserted `WREADY`, creating a race condition where `mem[AWADDR[5:2]]` could
capture the wrong address if `AWVALID` and `WVALID` arrived in different cycles.

**Fix:** A dedicated `aw_active` flip-flop latches the write address once
`AWREADY` fires. `WREADY` is only asserted when `aw_active` is set, ensuring
the correct latched address drives the memory write.

### Byte-enable write strobes (`WSTRB`)
Full `WSTRB[3:0]` support allows partial-word register updates without a
read-modify-write cycle, which is mandatory for control-register peripherals
(e.g., clearing a single status bit).

### SLVERR on address decode failure
Any access outside the 64-byte aperture, or to a non-word-aligned address,
returns `SLVERR`. This follows the AXI4 spec requirement that slaves must
respond on every transaction — never deadlock.

---

## Protocol Assertions (SVA)

Defined in `axi4lite_if.sv` and active during simulation:

| Assertion | Checks |
|---|---|
| `AST_AWVALID_STABLE` | Master must not drop `AWVALID` before `AWREADY` |
| `AST_WVALID_STABLE` | Master must not drop `WVALID` before `WREADY` |
| `AST_ARVALID_STABLE` | Master must not drop `ARVALID` before `ARREADY` |
| `AST_AWADDR_STABLE` | `AWADDR` must be stable while awaiting handshake |
| `AST_RVALID_STABLE` | Slave must hold `RVALID` until `RREADY` |
| `AST_RESET_OUTPUTS` | All slave outputs low during reset |

---

## Functional Coverage (`cg_axi4lite`)

| Coverpoint | Goal |
|---|---|
| `cp_write_handshake` | Full AW+W simultaneous handshake |
| `cp_read_handshake` | AR handshake |
| `cp_bresp` | Both OKAY and SLVERR write responses |
| `cp_rresp` | Both OKAY and SLVERR read responses |
| `cp_wr_addr` | All 16 write address locations hit |
| `cp_rd_addr` | All 16 read address locations hit |
| `cp_wstrb` | All byte-strobe patterns (byte0/1/2/3 + full word) |
| `cx_wr_addr_resp` | Cross of write address × write response type |

---

## Test Cases

| TC | Scenario | Expected Result |
|---|---|---|
| TC1 | Basic write → read-back | `RDATA == WDATA`, BRESP/RRESP = OKAY |
| TC2 | All 16 locations swept | 16/16 read-back matches |
| TC3 | Byte-enable strobes | Partial word updates verified per byte |
| TC4 | Out-of-range address (0x40) | BRESP = SLVERR, RRESP = SLVERR |
| TC5 | Read-after-write hazard | Correct data returned immediately |

---

## How to Run

```bash
# Simulate (Cadence irun)
make sim

# View waveform (SimVision)
make waves

# Manual irun
irun -access +rwc -timescale 1ns/1ps -sv \
     rtl/axi4lite_if.sv rtl/axi4lite_slave.sv tb/axi4lite_tb.sv

# Clean
make clean
```


