import Clocks::*;
import EthernetTx::*;
import GetPut::*;
import StmtFSM::*;
import CommonEthernetTxTest::*;

(* synthesize *)
module mkTestEthernetTxChannelSensing(Empty);
    SyncBitIfc#(Bit#(1)) rxActivityIfc <- mkTestRxActivity(1);
    EthernetTx dut <- mkEthernetTx(rxActivityIfc);
    Reg#(UInt#(8)) idleCheck <- mkReg(0);
    Reg#(UInt#(10)) bitIndex <- mkReg(0);
    Reg#(UInt#(16)) tries <- mkReg(0);
    ArpReplyTarget peer = testTarget(0);

    mkAutoFSM(seq
        dut.request.put(peer);

        repeat (300) action
            assertPins(dut, 0, 0, "EthernetTx transmitted while rxActivity was high");
        endaction

        rxActivityIfc.send(0);

        while (idleCheck != 192) action
            assertPins(dut, 0, 0, "EthernetTx transmitted before channelIdleCycles elapsed");
            idleCheck <= idleCheck + 1;
        endaction

        waitForFrameStart(dut, tries, 16);
        checkFrameAfterStart(dut, peer, bitIndex);
        $display("SUCCESS");
        $finish(0);
    endseq);
endmodule
