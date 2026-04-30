/**
 * PLL configuration
 *
 * This Verilog module was generated automatically
 * using the gowin-pll tool.
 * Use at your own risk.
 *
 * Target-Device:                GW1NR-9 C6/I5
 * Given input frequency:        27.000 MHz
 * Requested output frequency:   80.000 MHz
 * Achieved output frequency:    81.000 MHz
 */

module pll_main(
        input  clock_in,
        output clock_out,
        output clock_out_tx,
        output locked
    );

    rPLL #(
        .FCLKIN("27"),
        .IDIV_SEL(0), // -> PFD = 27.0 MHz (range: 3-400 MHz)
        .FBDIV_SEL(2), // -> CLKOUT = 81.0 MHz (range: 400-600 MHz)
        .ODIV_SEL(8), // -> VCO = 648.0 MHz (range: 600-1200 MHz)
        .DYN_SDIV_SEL(4), // -> CLKOUTD = 20.25 MHz
        .CLKOUTD_SRC("CLKOUT")
    ) pll (.CLKOUTP(), .CLKOUTD(clock_out_tx), .CLKOUTD3(), .RESET(1'b0), .RESET_P(1'b0), .CLKFB(1'b0), .FBDSEL(6'b0), .IDSEL(6'b0), .ODSEL(6'b0), .PSDA(4'b0), .DUTYDA(4'b0), .FDLY(4'b0), 
        .CLKIN(clock_in), // 27 MHz
        .CLKOUT(clock_out), // 81.0 MHz
        .LOCK(locked)
    );

endmodule
