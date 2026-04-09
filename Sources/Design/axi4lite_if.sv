// =============================================================================
// File        : axi4lite_if.sv
// Project     : AXI4-Lite Slave Memory Controller
// Author      : Vinayak Venkappa Pujeri (Vision)
// Description : AXI4-Lite interface bundle with protocol assertions
// =============================================================================

interface axi4lite_if (
  input logic ACLK,
  input logic ARESETn
);

  // ---------------------------------------------------------------------------
  // Write Address Channel (AW)
  // ---------------------------------------------------------------------------
  logic [31:0] AWADDR;
  logic        AWVALID;
  logic        AWREADY;

  // ---------------------------------------------------------------------------
  // Write Data Channel (W)
  // ---------------------------------------------------------------------------
  logic [31:0] WDATA;
  logic [3:0]  WSTRB;      // byte-enable strobes
  logic        WVALID;
  logic        WREADY;

  // ---------------------------------------------------------------------------
  // Write Response Channel (B)
  // ---------------------------------------------------------------------------
  logic [1:0]  BRESP;      // 2'b00=OKAY, 2'b10=SLVERR
  logic        BVALID;
  logic        BREADY;

  // ---------------------------------------------------------------------------
  // Read Address Channel (AR)
  // ---------------------------------------------------------------------------
  logic [31:0] ARADDR;
  logic        ARVALID;
  logic        ARREADY;

  // ---------------------------------------------------------------------------
  // Read Data Channel (R)
  // ---------------------------------------------------------------------------
  logic [31:0] RDATA;
  logic [1:0]  RRESP;      // 2'b00=OKAY, 2'b10=SLVERR
  logic        RVALID;
  logic        RREADY;

  // ===========================================================================
  // AXI4-Lite Protocol Assertions
  // ===========================================================================

  // AWVALID must not deassert until AWREADY is seen
  property p_awvalid_stable;
    @(posedge ACLK) disable iff (!ARESETn)
    (AWVALID && !AWREADY) |=> AWVALID;
  endproperty
  AST_AWVALID_STABLE: assert property (p_awvalid_stable)
    else $error("[ASSERTION FAIL] AWVALID deasserted before AWREADY handshake");

  // WVALID must not deassert until WREADY is seen
  property p_wvalid_stable;
    @(posedge ACLK) disable iff (!ARESETn)
    (WVALID && !WREADY) |=> WVALID;
  endproperty
  AST_WVALID_STABLE: assert property (p_wvalid_stable)
    else $error("[ASSERTION FAIL] WVALID deasserted before WREADY handshake");

  // ARVALID must not deassert until ARREADY is seen
  property p_arvalid_stable;
    @(posedge ACLK) disable iff (!ARESETn)
    (ARVALID && !ARREADY) |=> ARVALID;
  endproperty
  AST_ARVALID_STABLE: assert property (p_arvalid_stable)
    else $error("[ASSERTION FAIL] ARVALID deasserted before ARREADY handshake");

  // AWADDR must be stable while AWVALID is high and AWREADY is not
  property p_awaddr_stable;
    @(posedge ACLK) disable iff (!ARESETn)
    (AWVALID && !AWREADY) |=> $stable(AWADDR);
  endproperty
  AST_AWADDR_STABLE: assert property (p_awaddr_stable)
    else $error("[ASSERTION FAIL] AWADDR changed mid-handshake");

  // RVALID must not deassert until RREADY is seen
  property p_rvalid_stable;
    @(posedge ACLK) disable iff (!ARESETn)
    (RVALID && !RREADY) |=> RVALID;
  endproperty
  AST_RVALID_STABLE: assert property (p_rvalid_stable)
    else $error("[ASSERTION FAIL] RVALID deasserted before RREADY handshake");

  // After reset, all slave outputs must be deasserted
  property p_reset_outputs;
    @(posedge ACLK)
    (!ARESETn) |-> (!AWREADY && !WREADY && !BVALID && !ARREADY && !RVALID);
  endproperty
  AST_RESET_OUTPUTS: assert property (p_reset_outputs)
    else $error("[ASSERTION FAIL] Slave outputs not cleared during reset");

  // ===========================================================================
  // Functional Coverage
  // ===========================================================================
  covergroup cg_axi4lite @(posedge ACLK);
    // Write handshake observed
    cp_write_handshake: coverpoint (AWVALID & AWREADY & WVALID & WREADY) {
      bins handshake = {1'b1};
    }
    // Read handshake observed
    cp_read_handshake: coverpoint (ARVALID & ARREADY) {
      bins handshake = {1'b1};
    }
    // Write response
    cp_bresp: coverpoint BRESP {
      bins okay  = {2'b00};
      bins slverr= {2'b10};
    }
    // Read response
    cp_rresp: coverpoint RRESP {
      bins okay  = {2'b00};
      bins slverr= {2'b10};
    }
    // Address range coverage (word-aligned, 16-entry memory)
    cp_wr_addr: coverpoint AWADDR[5:2] {
      bins addr[] = {[0:15]};
    }
    cp_rd_addr: coverpoint ARADDR[5:2] {
      bins addr[] = {[0:15]};
    }
    // Write strobe patterns
    cp_wstrb: coverpoint WSTRB {
      bins full_word  = {4'b1111};
      bins byte0      = {4'b0001};
      bins byte1      = {4'b0010};
      bins byte2      = {4'b0100};
      bins byte3      = {4'b1000};
      bins others     = default;
    }
    // Cross: write address × write response
    cx_wr_addr_resp: cross cp_wr_addr, cp_bresp;
  endgroup

  cg_axi4lite cg_inst = new();

endinterface : axi4lite_if

