import GetPut::*;

interface RxActivityDetector;
    interface Put#(Bit#(1)) in;
    method Bool active;
endinterface

module mkRxActivityDetector(RxActivityDetector);
    // Digital carrier-sense heuristic for the simplified lab AFE. Commercial
    // PHYs usually detect carrier from analog signal energy; here we look for
    // Manchester-like timing so idle noise is not treated as RX activity.
    Reg#(Bit#(1)) prev <- mkReg(0);
    Reg#(Bit#(5)) how_long <- mkReg(0);
    Reg#(Bit#(5)) score <- mkReg(0);

    interface Put in;
        method Action put(Bit#(1) in);
            prev <= in;
            if (in == prev) begin
                // No input transition: extend the current pulse duration
                if (how_long < 16) begin
                    // Saturate the duration counter to avoid wraparound
                    how_long <= how_long + 1;
                end else begin
                    // Long idle periods reduce the confidence that a frame is present
                    if (score != 0) begin
                        score <= score - 1;
                    end
                end
            end else begin
                // Input transition: classify the completed pulse duration
                how_long <= 0;
                if (how_long == 3 || how_long == 4 || how_long == 5 || how_long == 7 || how_long == 8 || how_long == 9) begin
                    // Durations compatible with Manchester timing increase confidence
                    if (score < 10) begin
                        score <= score + 2;
                    end
                end else begin
                    // Unexpected pulse durations decrease confidence
                    if (score != 0) begin
                        score <= score - 1;
                    end
                end
            end
        endmethod
    endinterface

    method active = score > 8;
endmodule
