// =============================================================================
// File        : axi4lite_slave.sv
// Project     : AXI4-Lite Slave Memory Controller
// Author      : Vinayak Venkappa Pujeri (Vision)
// Description : AXI4-Lite compliant slave with 16×32-bit memory, byte-enable
//               write strobes, SLVERR on out-of-range addresses, and a clean
//               two-phase handshake (AWREADY/WREADY independent).
//
// Memory Map  : Base + 0x00 0x3C  (16 word-aligned locations)
//               Addresses outside this range return SLVERR.
//
// Compliance  : ARM IHI0022E AXI4-Lite (single-outstanding transaction)
// =============================================================================

module axi4lite_slave #(
  parameter MEM_DEPTH = 16,             // number of 32-bit words
  parameter BASE_ADDR = 32'h0000_0000
) (
  axi4lite_if axi
);

  // ---------------------------------------------------------------------------
  // Internal memory
  // ---------------------------------------------------------------------------
  logic [31:0] mem [0:MEM_DEPTH-1];

  // ---------------------------------------------------------------------------
  // Address decode helpers
  // ---------------------------------------------------------------------------
  localparam ADDR_BITS = $clog2(MEM_DEPTH) + 2;   // e.g. 6 bits for 16 words

  function automatic logic addr_in_range (input logic [31:0] addr);
    return (addr >= BASE_ADDR) &&
           (addr < BASE_ADDR + (MEM_DEPTH << 2)) &&
           (addr[1:0] == 2'b00);         // must be word-aligned
  endfunction

  function automatic logic [3:0] addr_to_idx (input logic [31:0] addr);
    return addr[ADDR_BITS-1:2];
  endfunction

  // ---------------------------------------------------------------------------
  // Write address channel latch & hold address
  // ---------------------------------------------------------------------------
  logic [31:0] aw_addr_lat;
  logic        aw_active;          // write address has been accepted

  always_ff @(posedge axi.ACLK or negedge axi.ARESETn) begin
    if (!axi.ARESETn) begin
      axi.AWREADY <= 1'b0;
      aw_addr_lat <= '0;
      aw_active   <= 1'b0;
    end else begin
      if (axi.AWVALID && !axi.AWREADY && !aw_active) begin
        axi.AWREADY <= 1'b1;
        aw_addr_lat <= axi.AWADDR;
        aw_active   <= 1'b1;
      end else begin
        axi.AWREADY <= 1'b0;
        // clear after write data is accepted
        if (axi.WVALID && axi.WREADY)
          aw_active <= 1'b0;
      end
    end
  end

  // ---------------------------------------------------------------------------
  // Write data channel + write response
  // ---------------------------------------------------------------------------
  always_ff @(posedge axi.ACLK or negedge axi.ARESETn) begin
    if (!axi.ARESETn) begin
      axi.WREADY <= 1'b0;
      axi.BVALID <= 1'b0;
      axi.BRESP  <= 2'b00;
    end else begin
      // De-assert BVALID once master acknowledges
      if (axi.BVALID && axi.BREADY)
        axi.BVALID <= 1'b0;

      if (axi.WVALID && aw_active && !axi.WREADY) begin
        axi.WREADY <= 1'b1;

        if (addr_in_range(aw_addr_lat)) begin
          // Apply byte-enable write strobes
          if (axi.WSTRB[0]) mem[addr_to_idx(aw_addr_lat)][7:0]   <= axi.WDATA[7:0];
          if (axi.WSTRB[1]) mem[addr_to_idx(aw_addr_lat)][15:8]  <= axi.WDATA[15:8];
          if (axi.WSTRB[2]) mem[addr_to_idx(aw_addr_lat)][23:16] <= axi.WDATA[23:16];
          if (axi.WSTRB[3]) mem[addr_to_idx(aw_addr_lat)][31:24] <= axi.WDATA[31:24];
          axi.BRESP <= 2'b00;            // OKAY
        end else begin
          axi.BRESP <= 2'b10;            // SLVERR out of range
        end

        axi.BVALID <= 1'b1;
      end else begin
        axi.WREADY <= 1'b0;
      end
    end
  end

  // ---------------------------------------------------------------------------
  // Read address + read data channels
  // ---------------------------------------------------------------------------
  always_ff @(posedge axi.ACLK or negedge axi.ARESETn) begin
    if (!axi.ARESETn) begin
      axi.ARREADY <= 1'b0;
      axi.RVALID  <= 1'b0;
      axi.RDATA   <= '0;
      axi.RRESP   <= 2'b00;
    end else begin
      // De-assert RVALID once master acknowledges
      if (axi.RVALID && axi.RREADY)
        axi.RVALID <= 1'b0;

      if (axi.ARVALID && !axi.ARREADY && !axi.RVALID) begin
        axi.ARREADY <= 1'b1;

        if (addr_in_range(axi.ARADDR)) begin
          axi.RDATA  <= mem[addr_to_idx(axi.ARADDR)];
          axi.RRESP  <= 2'b00;           // OKAY
        end else begin
          axi.RDATA  <= 32'hDEAD_C0DE;  // error sentinel
          axi.RRESP  <= 2'b10;           // SLVERR
        end

        axi.RVALID <= 1'b1;
      end else begin
        axi.ARREADY <= 1'b0;
      end
    end
  end

  // ---------------------------------------------------------------------------
  // Simulation-only: memory initialisation
  // ---------------------------------------------------------------------------
  // synthesis translate_off
  initial begin
    foreach (mem[i]) mem[i] = 32'h0;
  end
  // synthesis translate_on

endmodule : axi4lite_slave
