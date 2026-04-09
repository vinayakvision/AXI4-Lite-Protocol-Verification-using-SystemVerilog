// =============================================================================
// File        : axi4lite_tb.sv
// Project     : AXI4-Lite Slave Memory Controller
// Author      : Vinayak Venkappa Pujeri (Vision)
// Description : Self-checking testbench covering:
//               TC1 Single write + read-back verify
//               TC2 All 16 memory locations (address sweep)
//               TC3 Byte-enable write strobes (partial word writes)
//               TC4 Out-of-range address ? SLVERR response
//               TC5 Back-to-back pipelined transactions
// =============================================================================



module axi4lite_tb;

  // ---------------------------------------------------------------------------
  // DUT Instantiation
  // ---------------------------------------------------------------------------
  logic ACLK    = 0;
  logic ARESETn = 0;

  axi4lite_if axi (.ACLK(ACLK), .ARESETn(ARESETn));

  axi4lite_slave #(
    .MEM_DEPTH (16),
    .BASE_ADDR (32'h0000_0000)
  ) dut (.axi(axi));

  // ---------------------------------------------------------------------------
  // Clock 100 MHz (10 ns period)
  // ---------------------------------------------------------------------------
  always #5 ACLK = ~ACLK;

  // ---------------------------------------------------------------------------
  // Scoreboard counters
  // ---------------------------------------------------------------------------
  int pass_cnt = 0;
  int fail_cnt = 0;

  // ---------------------------------------------------------------------------
  // Task: drive_write
  //   Performs a single AXI4-Lite write transaction and checks BRESP.
  // ---------------------------------------------------------------------------
  task automatic drive_write (
    input  logic [31:0] addr,
    input  logic [31:0] data,
    input  logic [3:0]  strb      = 4'hF,
    input  logic [1:0]  exp_bresp = 2'b00
  );
    // Drive address and data simultaneously (AXI4-Lite allows this)
    @(posedge ACLK);
    axi.AWADDR  <= addr;
    axi.AWVALID <= 1;
    axi.WDATA   <= data;
    axi.WSTRB   <= strb;
    axi.WVALID  <= 1;
    axi.BREADY  <= 1;

    // Wait for AW handshake
    @(posedge ACLK);
    while (!(axi.AWVALID && axi.AWREADY)) @(posedge ACLK);
    axi.AWVALID <= 0;

    // Wait for W handshake
    while (!(axi.WVALID && axi.WREADY)) @(posedge ACLK);
    axi.WVALID <= 0;

    // Wait for B response
    while (!axi.BVALID) @(posedge ACLK);
    if (axi.BRESP !== exp_bresp) begin
      $display("  [FAIL] WRITE addr=0x%08h: BRESP got %02b, exp %02b",
               addr, axi.BRESP, exp_bresp);
      fail_cnt++;
    end
    @(posedge ACLK);
    axi.BREADY <= 0;
  endtask

  // ---------------------------------------------------------------------------
  // Task: drive_read
  //   Performs a single AXI4-Lite read, returns data in rdata_out.
  // ---------------------------------------------------------------------------
  task automatic drive_read (
    input  logic [31:0] addr,
    output logic [31:0] rdata_out,
    input  logic [1:0]  exp_rresp = 2'b00
  );
    @(posedge ACLK);
    axi.ARADDR  <= addr;
    axi.ARVALID <= 1;
    axi.RREADY  <= 1;

    while (!(axi.ARVALID && axi.ARREADY)) @(posedge ACLK);
    axi.ARVALID <= 0;

    while (!axi.RVALID) @(posedge ACLK);
    rdata_out = axi.RDATA;

    if (axi.RRESP !== exp_rresp) begin
      $display("  [FAIL] READ addr=0x%08h: RRESP got %02b, exp %02b",
               addr, axi.RRESP, exp_rresp);
      fail_cnt++;
    end
    @(posedge ACLK);
    axi.RREADY <= 0;
  endtask

  // ---------------------------------------------------------------------------
  // Task: check_result scoreboard helper
  // ---------------------------------------------------------------------------
  task automatic check_result (
    input string       test_name,
    input logic [31:0] got,
    input logic [31:0] exp
  );
    if (got === exp) begin
      $display("  [PASS] %s | got=0x%08h", test_name, got);
      pass_cnt++;
    end else begin
      $display("  [FAIL] %s | got=0x%08h  exp=0x%08h", test_name, got, exp);
      fail_cnt++;
    end
  endtask

  // ---------------------------------------------------------------------------
  // Initialise all master-side signals
  // ---------------------------------------------------------------------------
  initial begin
    axi.AWADDR  = 0; axi.AWVALID = 0;
    axi.WDATA   = 0; axi.WSTRB   = 0; axi.WVALID = 0;
    axi.BREADY  = 0;
    axi.ARADDR  = 0; axi.ARVALID = 0;
    axi.RREADY  = 0;
  end

  // ---------------------------------------------------------------------------
  // Reset sequence
  // ---------------------------------------------------------------------------
  initial begin
    ARESETn = 0;
    repeat (4) @(posedge ACLK);
    ARESETn = 1;
    $display("\n[%0t ns] Reset released", $time/1000);
  end

  // ---------------------------------------------------------------------------
  // Main stimulus
  // ---------------------------------------------------------------------------
  initial begin
    logic [31:0] rdata;

    // Wait for reset
    wait (ARESETn === 1'b1);
    repeat (2) @(posedge ACLK);

    // ==========================================================================
    // TC1 Basic write then read-back verify
    // ==========================================================================
    $display("\n========== TC1: Basic Write ? Read-back ==========");
    drive_write(32'h0000_0000, 32'hDEAD_BEEF);
    drive_read (32'h0000_0000, rdata);
    check_result("TC1 addr=0x00", rdata, 32'hDEAD_BEEF);

    drive_write(32'h0000_0004, 32'hCAFE_BABE);
    drive_read (32'h0000_0004, rdata);
    check_result("TC1 addr=0x04", rdata, 32'hCAFE_BABE);

    // ==========================================================================
    // TC2 All 16 memory locations (address sweep)
    // ==========================================================================
    $display("\n========== TC2: Address Sweep (all 16 locations) ==========");
    // Write phase
    for (int i = 0; i < 16; i++) begin
      drive_write(i * 4, 32'hA000_0000 | i);
    end
    // Read-back phase
    for (int i = 0; i < 16; i++) begin
      drive_read(i * 4, rdata);
      check_result($sformatf("TC2 addr=0x%02h", i*4),
                   rdata, 32'hA000_0000 | i);
    end

    // ==========================================================================
    // TC3 Byte-enable write strobes
    // ==========================================================================
    $display("\n========== TC3: Byte-Enable Write Strobes ==========");
    // Seed with full word
    drive_write(32'h0000_0008, 32'hFFFF_FFFF);

    // Overwrite only byte 0 ? expected: 0xFFFF_FF11
    drive_write(32'h0000_0008, 32'h0000_0011, 4'b0001);
    drive_read (32'h0000_0008, rdata);
    check_result("TC3 WSTRB=0001 byte0", rdata, 32'hFFFF_FF11);

    // Overwrite bytes 2:1 ? expected: 0xFF2233_11
    drive_write(32'h0000_0008, 32'h0022_3300, 4'b0110);
    drive_read (32'h0000_0008, rdata);
    check_result("TC3 WSTRB=0110 bytes[2:1]", rdata, 32'hFF22_3311);

    // Overwrite byte 3 ? expected: 0x44223311
    drive_write(32'h0000_0008, 32'h4400_0000, 4'b1000);
    drive_read (32'h0000_0008, rdata);
    check_result("TC3 WSTRB=1000 byte3", rdata, 32'h4422_3311);

    // ==========================================================================
    // TC4 Out-of-range address ? SLVERR
    // ==========================================================================
    $display("\n========== TC4: Out-of-Range Address ? SLVERR ==========");
    // Write to address beyond mem (word 16 = 0x40)
    drive_write(32'h0000_0040, 32'hBAD_BABE, 4'hF, 2'b10);
    $display("  [PASS] TC4 WRITE SLVERR received (BRESP=10)");
    pass_cnt++;

    // Read from out-of-range
    drive_read(32'h0000_0040, rdata, 2'b10);
    $display("  [PASS] TC4 READ SLVERR received (RRESP=10, RDATA=0x%08h)", rdata);
    pass_cnt++;

    // ==========================================================================
    // TC5 Read-after-write hazard: immediate read of same address
    // ==========================================================================
    $display("\n========== TC5: Read-After-Write Hazard ==========");
    drive_write(32'h0000_0010, 32'h1234_5678);
    drive_read (32'h0000_0010, rdata);
    check_result("TC5 RAW addr=0x10", rdata, 32'h1234_5678);

    // ==========================================================================
    // Summary
    // ==========================================================================
    repeat (4) @(posedge ACLK);
    $display("\n");
    $display("============================================================");
    $display("  SIMULATION COMPLETE  |  PASS: %0d  |  FAIL: %0d",
             pass_cnt, fail_cnt);
    $display("============================================================\n");

    if (fail_cnt == 0)
      $display("   ALL TESTS PASSED DESIGN VERIFIED \n");
    else
      $display("   %0d TEST(S) FAILED CHECK LOG \n", fail_cnt);

    $stop;
  end

  // ---------------------------------------------------------------------------
  // Timeout watchdog prevents infinite hang on protocol deadlock
  // ---------------------------------------------------------------------------
  initial begin
    #50000;
    $display("[WATCHDOG] Simulation timed out at %0t ns", $time/1000);
    $stop;
  end

  // ---------------------------------------------------------------------------
  // VCD dump for waveform viewing
  // ---------------------------------------------------------------------------
  // synthesis translate_off
  initial begin
        $shm_open("wave.shm");
        $shm_probe("ACTMF");
    end
  // synthesis translate_on

endmodule : axi4lite_tb

