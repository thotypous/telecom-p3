import GetPut::*;
import FIFOF::*;
import CommonIfc::*;

module mkManchesterDecoder(FrameBitProcessor);
    Reg#(Maybe#(Bit#(1))) prev <- mkReg(Invalid);
    Reg#(Bit#(3)) i <- mkReg(0);
    FIFOF#(Maybe#(Bit#(1))) outFifo <- mkFIFOF;

    interface Put in;
        method Action put(Maybe#(Bit#(1)) in);
            // TODO: decode the Manchester stream produced by FrameDelimiter.
            // Valid inputs are samples from inside a frame; Invalid marks the end
            // of a frame and should be propagated after resetting decoder state.
        endmethod
    endinterface
    interface out = toGet(outFifo);
endmodule
