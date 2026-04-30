import Clocks::*;
import EthernetTx::*;
import GetPut::*;
import StmtFSM::*;
import CommonEthernetTxTest::*;

(* synthesize *)
module mkTestEthernetTxManchester(Empty);
    SyncBitIfc#(Bit#(1)) rxActivityIfc <- mkTestRxActivity(0);
    EthernetTx dut <- mkEthernetTx(rxActivityIfc);
    Reg#(UInt#(2)) targetIndex <- mkReg(0);
    Reg#(UInt#(10)) bitIndex <- mkReg(0);
    Reg#(UInt#(16)) tries <- mkReg(0);

    mkAutoFSM(seq
        while (targetIndex != 3) seq
            dut.request.put(testTarget(targetIndex));
            waitForFrameStart(dut, tries, 5000);
            checkFrameAfterStart(dut, testTarget(targetIndex), bitIndex);
            targetIndex <= targetIndex + 1;
        endseq
        $display("SUCCESS");
        $finish(0);
    endseq);
endmodule
