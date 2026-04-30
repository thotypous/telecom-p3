import GetPut::*;
import FIFOF::*;
import CommonIfc::*;

module mkSFDLocator(FrameBitProcessor);
    Reg#(Bit#(1)) prev <- mkReg(0);
    Reg#(Bool) afterSfd <- mkReg(False);
    FIFOF#(Maybe#(Bit#(1))) outFifo <- mkFIFOF;

    interface Put in;
        method Action put(Maybe#(Bit#(1)) in);
            // TODO: suppress the Ethernet preamble and SFD, then forward only the
            // frame bits after the SFD.  Invalid marks the end of a frame and
            // should be propagated after resetting locator state.
        endmethod
    endinterface
    interface out = toGet(outFifo);
endmodule
