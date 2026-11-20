/*
/   Title: Testbench Macros
/   Author: Samuel Darrall
/   Date: 20-NOV-2026
*/

`ifndef TB_MACROS_SVH
`define TB_MACROS_SVH

`ifndef TB_NO_TIMESCALE
`timescale 1ns/1ps
`endif

`ifndef TB_CLK
`define TB_CLK clk
`endif

`ifndef TB_MAX_ERRORS
`define TB_MAX_ERRORS 20
`endif

`define TB_SETUP \
  int    tb_errors = 0; \
  int    tb_checks = 0; \
  int    tb_tests  = 0; \
  string tb_test_name = "<none>";

`define TEST(_NAME_) \
  begin \
    tb_tests++; \
    tb_test_name = _NAME_; \
    $display("\n[%0t] TEST %0d: %s", $time, tb_tests, _NAME_); \
  end

`define TB_FINISH \
  begin \
    $display(" %0d test(s), %0d check(s), %0d error(s)", tb_tests, tb_checks, tb_errors); \
    if (tb_errors == 0) begin \
      $display(" RESULT: PASS"); \
      $finish; \
    end else begin \
      $display(" RESULT: FAIL"); \
      $fatal(1, "testbench failed"); \
    end \
  end

`define CLOCK(_SIG_, _PERIOD_) \
  logic _SIG_ = 1'b0; \
  always #((_PERIOD_)/2.0) _SIG_ = ~_SIG_;

`define CLOCK_MHZ(_SIG_, _MHZ_) \
  logic _SIG_ = 1'b0; \
  always #(500.0ns/(_MHZ_)) _SIG_ = ~_SIG_;

`define DRIVE_CLOCK_MHZ(_SIG_, _MHZ_) \
  initial _SIG_ = 1'b0; \
  always #(500.0ns/(_MHZ_)) _SIG_ = ~_SIG_;

`define clock_1m    `CLOCK_MHZ(`TB_CLK, 1)
`define clock_10m   `CLOCK_MHZ(`TB_CLK, 10)
`define clock_25m   `CLOCK_MHZ(`TB_CLK, 25)
`define clock_27m   `CLOCK_MHZ(`TB_CLK, 27)
`define clock_50m   `CLOCK_MHZ(`TB_CLK, 50)
`define clock_100m  `CLOCK_MHZ(`TB_CLK, 100)

`define RESET(_SIG_, _CYCLES_) \
  logic _SIG_ = 1'b1; \
  initial begin \
    repeat (_CYCLES_) @(posedge `TB_CLK); \
    @(negedge `TB_CLK) _SIG_ = 1'b0; \
  end

`define RESET_N(_SIG_, _CYCLES_) \
  logic _SIG_ = 1'b0; \
  initial begin \
    repeat (_CYCLES_) @(posedge `TB_CLK); \
    @(negedge `TB_CLK) _SIG_ = 1'b1; \
  end

`define TICK(_N_)     repeat (_N_) @(posedge `TB_CLK);
`define TICK_NEG(_N_) repeat (_N_) @(negedge `TB_CLK);

`define WAIT_FOR(_COND_, _MAX_CYCLES_) \
  begin \
    int tb_wait_n; \
    tb_wait_n = 0; \
    while (!(_COND_) && tb_wait_n < (_MAX_CYCLES_)) begin \
      @(posedge `TB_CLK); \
      tb_wait_n++; \
    end \
    tb_checks++; \
    if (!(_COND_)) begin \
      `TB_FAIL($sformatf("WAIT_FOR timed out after %0d cycles: %s", _MAX_CYCLES_, `"_COND_`")) \
    end \
  end

`define TIMEOUT(_T_) \
  initial begin \
    #(_T_); \
    $display("[%0t] *** TIMEOUT after %0t ***", $time, _T_); \
    $fatal(1, "timeout"); \
  end

`define TB_FAIL(_MSG_) \
  begin \
    tb_errors++; \
    $display("[%0t] FAIL (%s) %s  @ %s:%0d", $time, tb_test_name, _MSG_, `__FILE__, `__LINE__); \
    if (`TB_MAX_ERRORS != 0 && tb_errors >= `TB_MAX_ERRORS) begin \
      $display("Too many errors (%0d), stopping.", tb_errors); \
      $fatal(1, "max errors reached"); \
    end \
  end

`define CHECK_EQ(_ACTUAL_, _EXPECTED_) \
  begin \
    tb_checks++; \
    if ((_ACTUAL_) !== (_EXPECTED_)) \
      `TB_FAIL($sformatf("%s = 0x%0h, expected 0x%0h", `"_ACTUAL_`", (_ACTUAL_), (_EXPECTED_))) \
  end

`define CHECK_NE(_ACTUAL_, _UNEXPECTED_) \
  begin \
    tb_checks++; \
    if ((_ACTUAL_) === (_UNEXPECTED_)) \
      `TB_FAIL($sformatf("%s = 0x%0h, should differ", `"_ACTUAL_`", (_ACTUAL_))) \
  end

`define CHECK_TRUE(_COND_) \
  begin \
    tb_checks++; \
    if ((_COND_) !== 1'b1) \
      `TB_FAIL($sformatf("expected true: %s", `"_COND_`")) \
  end

`define CHECK_RANGE(_VAL_, _LO_, _HI_) \
  begin \
    tb_checks++; \
    if ((_VAL_) < (_LO_) || (_VAL_) > (_HI_)) \
      `TB_FAIL($sformatf("%s = %0d, expected in [%0d, %0d]", `"_VAL_`", (_VAL_), (_LO_), (_HI_))) \
  end

`define CHECK_KNOWN(_SIG_) \
  begin \
    tb_checks++; \
    if ($isunknown(_SIG_)) \
      `TB_FAIL($sformatf("%s has X/Z bits: %b", `"_SIG_`", (_SIG_))) \
  end

`define NO_X_AFTER_RESET(_SIG_, _RST_N_) \
  always @(posedge `TB_CLK) \
    if ((_RST_N_) === 1'b1 && $isunknown(_SIG_)) \
      `TB_FAIL($sformatf("%s went X/Z: %b", `"_SIG_`", (_SIG_)))

`define TB_SEED \
  begin \
    int unsigned tb_seed; \
    if (!$value$plusargs("seed=%d", tb_seed)) tb_seed = 1; \
    void'($urandom(tb_seed)); \
    $display("[tb] seed = %0d   (rerun with +seed=%0d)", tb_seed, tb_seed); \
  end

`define RAND_RANGE(_LO_, _HI_) $urandom_range(_HI_, _LO_)

`define INFO(_MSG_) $display("[%0t] INFO  %s", $time, _MSG_);

`define DEBUG(_MSG_) if ($test$plusargs("verbose")) $display("[%0t] DEBUG %s", $time, _MSG_);

`define DUMP(_TOP_) \
  initial if ($test$plusargs("dump")) begin \
    $dumpfile({`"_TOP_`", ".vcd"}); \
    $dumpvars(0, _TOP_); \
  end

`endif // TB_MACROS_SVH
